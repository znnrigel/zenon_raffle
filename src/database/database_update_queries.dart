import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../variables/global.dart';
import 'database_service.dart';

Future<void> updatePlayers(List<AccountBlock> bets, Address winner) async {
  // format the input to facilitate table updates
  List<Map<String, dynamic>> players = [];
  for (AccountBlock b in bets) {
    bool found = false;
    for (var p in players) {
      if (p['address'] == b.address.toString()) {
        found = true;
        p['numberOfBets'] += 1;
        break;
      }
    }
    if (!found) {
      players.add({
        'address': b.address.toString(),
        'numberOfBets': 1,
        'wonLastRound': winner == b.address
      });
    }
  }

  String upsertQuery(String address, int numberOfBets, bool wonLastRound) => '''
      INSERT INTO ${Table.players} (address, numberOfBets, roundsPlayed, roundsWon)
      VALUES ('$address', $numberOfBets, 1, ${wonLastRound ? 1 : 0})
      ON CONFLICT (address) DO UPDATE
      SET 
        numberOfBets = ${Table.players}.numberOfBets + EXCLUDED.numberOfBets,
        roundsPlayed = ${Table.players}.roundsPlayed + EXCLUDED.roundsPlayed,
        roundsWon = ${Table.players}.roundsWon + EXCLUDED.roundsWon;
      ''';

  List<String> playersQueries = [];
  for (var p in players) {
    playersQueries
        .add(upsertQuery(p['address'], p['numberOfBets'], p['wonLastRound']));
  }

  await lockTableAndInsert(Table.players, playersQueries);
}

Future<void> updateRounds(
  Address winner,
  Map<String, dynamic> results,
) async {
  String insertQuery(
    int startHeight,
    int endHeight,
    String tokenStandard,
    String pot,
    String winner,
    String hash,
    String seed,
    String winningTicket,
    int bpsBurn,
    int bpsDev,
    int bpsAirdrop,
    String airdropZts,
    String winnerAmount,
    String winnerBonus,
    String burnAmount,
    String devAmount,
    String airdropAmount,
    int airdropRecipients,
  ) =>
      '''
      INSERT INTO ${Table.rounds} (
        startHeight, endHeight, tokenStandard, pot, winner, hash, seed, 
        winningTicket, bpsBurn, bpsDev, bpsAirdrop, airdropZts, winnerAmount, 
        winnerBonus, burnAmount, devAmount, airdropAmount, airdropRecipients
      )
      VALUES (
        $startHeight, $endHeight, '$tokenStandard', '$pot', '$winner', '$hash', 
        '$seed', '$winningTicket', $bpsBurn, $bpsDev, $bpsAirdrop, '$airdropZts', 
        '$winnerAmount', '$winnerBonus', '$burnAmount', '$devAmount', 
        '$airdropAmount', $airdropRecipients
      );
      ''';

  await lockTableAndInsert(Table.rounds, [
    insertQuery(
      raffle.startHeight,
      raffle.endHeight,
      raffle.token.tokenStandard.toString(),
      raffle.pot.toString(),
      winner.toString(),
      results['hash'].toString(),
      results['seed']!.toString(),
      results['winningTicket']!.toString(),
      Config.bpsBurn,
      Config.bpsDev,
      Config.bpsAirdrop,
      Config.airdropZts.toString(),
      results['winnerAmount']!.toString(),
      '0', // set correct value later
      results['burnAmount']!.toString(),
      results['devAmount']!.toString(),
      results['airdropAmount']!.toString(),
      results['airdropRecipients']!,
    )
  ]);
}

Future<void> updateRoundsBonus(int roundNumber, BigInt bonus) async {
  String updateQuery(
    int roundNumber,
    String bonus,
  ) =>
      '''
      UPDATE ${Table.rounds} 
      SET winnerBonus = '$bonus'
      WHERE roundNumber = $roundNumber;
      ''';

  await lockTableAndInsert(
      Table.rounds, [updateQuery(roundNumber, bonus.toString())]);
}

Future<void> updateBets(List<AccountBlock> bets) async {
  String insertQuery(
    String hash,
    String address,
    int roundNumber,
    String tokenStandard,
    String amount,
    int momentumHeight,
  ) =>
      '''
      INSERT INTO ${Table.bets} (txHash, address, roundNumber, tokenStandard, amount, momentumHeight)
      VALUES ('$hash', '$address', $roundNumber, '$tokenStandard', '$amount', $momentumHeight);
      ''';

  int roundNumber = await getRoundNumber();

  List<String> betsQueries = [];
  for (AccountBlock b in bets) {
    betsQueries.add(insertQuery(
      b.hash.toString(),
      b.address.toString(),
      roundNumber,
      b.token!.tokenStandard.toString(),
      b.amount.toString(),
      b.confirmationDetail!.momentumHeight,
    ));
  }
  await lockTableAndInsert(Table.bets, betsQueries);
}

Future<void> updateZtsStats(
  List<AccountBlock> bets,
  Address winner,
  Map<String, dynamic> results,
) async {
  String table = '';
  if (raffle.token.tokenStandard == znnZts) table = Table.znnStats;
  if (raffle.token.tokenStandard == qsrZts) table = Table.qsrStats;
  if (raffle.token.tokenStandard == ppZts) table = Table.ppStats;

  // format the input to facilitate table updates
  List<Map<String, dynamic>> players = [];
  for (AccountBlock b in bets) {
    bool found = false;
    for (var p in players) {
      if (p['address'] == b.address.toString()) {
        found = true;
        p['betTotal'] += b.amount;
        b.amount > p['largestBet'] ? p['largestBet'] = b.amount : null;
        break;
      }
    }
    if (!found) {
      players.add({
        'address': b.address.toString(),
        'betTotal': b.amount,
        'largestBet': b.amount,
        'wonTotal':
            winner == b.address ? results['winnerAmount']! : BigInt.zero,
        'roundsPlayed': 1,
        'roundsWon': winner == b.address ? 1 : 0
      });
    }
  }

  String upsertQuery(
    String address,
    String betTotal,
    String largestBet,
    String wonTotal,
    int roundsPlayed,
    int roundsWon,
  ) =>
      '''
      INSERT INTO $table (address, betTotal, largestBet, wonTotal, roundsPlayed, roundsWon)
      VALUES ('$address', '$betTotal', '$largestBet', '$wonTotal', $roundsPlayed, $roundsWon)
      ON CONFLICT (address) DO UPDATE
      SET 
        betTotal = '$betTotal',
        largestBet = '$largestBet',
        wonTotal = '$wonTotal',
        roundsPlayed = $table.roundsPlayed + EXCLUDED.roundsPlayed,
        roundsWon = $table.roundsWon + EXCLUDED.roundsWon;
      ''';

  List<String> statsQueries = [];
  for (var p in players) {
    Map<String, dynamic> playerStats =
        await selectPlayerStats(p['address'], table);

    if (playerStats.isNotEmpty) {
      p['betTotal'] += playerStats['betTotal'];
      playerStats['largestBet'] > p['largestBet']
          ? p['largestBet'] = playerStats['largestBet']
          : null;
      p['roundsWon'] > 0
          ? p['wonTotal'] += playerStats['wonTotal']
          : p['wonTotal'] = playerStats['wonTotal'];
    }

    statsQueries.add(upsertQuery(
      p['address'],
      p['betTotal'].toString(),
      p['largestBet'].toString(),
      p['wonTotal'].toString(),
      p['roundsPlayed'],
      p['roundsWon'],
    ));
  }
  await lockTableAndInsert(table, statsQueries);
}

Future<void> lockTableAndInsert(String table, List<String> queries) async {
  try {
    await db.conn.runInTransaction(() async {
      await db.conn.query('LOCK TABLE $table IN SHARE MODE;').toList();

      for (String q in queries) {
        await db.conn.query(q).toList();
      }
      logger.log(Level.INFO, '$table updated successfully');
    });
  } catch (e) {
    logger.log(Level.WARNING, 'lockTableAndInsert(): $e');
    //dispose();
    //exit(1);
  }
}
