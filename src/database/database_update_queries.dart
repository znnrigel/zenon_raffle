import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../variables/global.dart';
import 'database_service.dart';

updatePlayers(List<AccountBlock> bets, Address winner) async {
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

insertNewRound(
  int roundNumber,
  int startHeight,
  int endHeight,
  String tokenStandard,
) async {
  await lockTableAndInsert(Table.rounds, [
    '''
      INSERT INTO ${Table.rounds} (
        roundNumber, active, startHeight, endHeight, tokenStandard, pot, winner, 
        hash, seed, winningTicket, bpsBurn, bpsDev, bpsAirdrop, airdropZts, 
        winnerAmount, winnerBonus, burnAmount, devAmount, airdropAmount, airdropRecipients
      )
      VALUES (
        $roundNumber, true, $startHeight, $endHeight, '$tokenStandard', 
        '0', '0', '0', '0', '0', 0, 0, 0, '0', '0', '0', '0', '0', '0', 0
      );
      '''
  ]);
}

updateRoundNoWinner(int roundNumber) async {
  await lockTableAndInsert(Table.rounds, [
    '''
      UPDATE ${Table.rounds} 
      SET active = false
      WHERE roundNumber = $roundNumber;
    '''
  ]);
}

updateRound(
  int roundNumber,
  BigInt pot,
  Address winner,
  Map<String, dynamic> results,
) async {
  await lockTableAndInsert(Table.rounds, [
    '''
      UPDATE ${Table.rounds} 
      SET
        active = false,
        pot = '${pot.toString()}',
        winner = '${winner.toString()}',
        hash = '${results['hash'].toString()}',
        seed = '${results['seed']!.toString()}',
        winningTicket = '${results['winningTicket']!.toString()}', 
        bpsBurn = ${Config.bpsBurn},
        bpsDev = ${Config.bpsDev},
        bpsAirdrop = ${Config.bpsAirdrop},
        airdropZts = '${Config.airdropZts.toString()}',
        winnerAmount = '${results['winnerAmount']!.toString()}',
        burnAmount = '${results['burnAmount']!.toString()}',
        devAmount = '${results['devAmount']!.toString()}',
        airdropAmount = '${results['airdropAmount']!.toString()}',
        airdropRecipients = ${results['airdropRecipients']!}
      WHERE roundNumber = $roundNumber;
      '''
  ]);
}

updateRoundBonus(int roundNumber, BigInt bonus) async {
  await lockTableAndInsert(Table.rounds, [
    '''
      UPDATE ${Table.rounds} 
      SET winnerBonus = '${bonus.toString()}'
      WHERE roundNumber = $roundNumber;
    '''
  ]);
}

updateBets(List<AccountBlock> bets) async {
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

  int roundNumber = (await getCurrentRoundStatus())['roundNumber'];

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

updateZtsStats(
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

    statsQueries.add('''
      INSERT INTO $table (address, betTotal, largestBet, wonTotal, roundsPlayed, roundsWon)
      VALUES (
      '${p['address']}', '${p['betTotal'].toString()}', 
      '${p['largestBet'].toString()}', '${p['wonTotal'].toString()}', 
      ${p['roundsPlayed']}, ${p['roundsWon']}
      )
      ON CONFLICT (address) DO UPDATE
      SET 
        betTotal = '${p['betTotal'].toString()}',
        largestBet = '${p['largestBet'].toString()}',
        wonTotal = '${p['wonTotal'].toString()}',
        roundsPlayed = $table.roundsPlayed + EXCLUDED.roundsPlayed,
        roundsWon = $table.roundsWon + EXCLUDED.roundsWon;
      ''');
  }
  await lockTableAndInsert(table, statsQueries);
}

lockTableAndInsert(String table, List<String> queries) async {
  try {
    await DatabaseService().conn.runInTransaction(() async {
      await DatabaseService()
          .conn
          .query('LOCK TABLE $table IN SHARE MODE;')
          .toList();

      for (String q in queries) {
        await DatabaseService().conn.query(q).toList();
      }
      logger.log(Level.INFO, '$table updated successfully');
    });
  } catch (e) {
    logger.log(Level.WARNING, 'lockTableAndInsert(): $e');
    //dispose();
    //exit(1);
  }
}
