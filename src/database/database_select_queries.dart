import 'package:postgresql2/postgresql.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'database_service.dart';

Future<Map<String, dynamic>> getCurrentRoundStatus() async {
  List r = await DatabaseService().conn.query(
    '''
      SELECT roundNumber, active
      FROM ${Table.rounds} 
      ORDER BY roundNumber DESC
      LIMIT 1;
      ''',
  ).toList();

  Map<String, dynamic> m = {};
  if (r.isNotEmpty) {
    try {
      m['roundNumber'] = r[0][0];
      m['active'] = r[0][1];
    } catch (e) {}
  }
  return m;
}

Future<int> getBetCountForRound(int roundNumber) async {
  List r = await DatabaseService().conn.query(
      'SELECT COUNT(*) FROM ${Table.bets} WHERE roundNumber = @roundNumber', {
    'roundNumber': roundNumber,
  }).toList();
  return r.isNotEmpty && r[0][0] != null ? r[0][0] : 0;
}

Future<int> getBetCountForZts(TokenStandard zts) async {
  List r = await DatabaseService().conn.query(
      'SELECT COUNT(*) FROM ${Table.bets} WHERE tokenStandard = @tokenStandard',
      {
        'tokenStandard': zts.toString(),
      }).toList();
  return r.isNotEmpty && r[0][0] != null ? r[0][0] : 0;
}

Future<int> getCount(String table) async {
  List r = await DatabaseService()
      .conn
      .query('SELECT COUNT(*) FROM $table')
      .toList();
  return r.isNotEmpty && r[0][0] != null ? r[0][0] : 0;
}

Future<Map<String, BigInt>> getAmountStats(String tokenStandard) async {
  List r = await DatabaseService().conn.query('''
      SELECT pot, burnAmount, airdropAmount
      FROM ${Table.rounds} 
      WHERE tokenStandard = @tokenStandard;
      ''', {'tokenStandard': tokenStandard}).toList();

  Map<String, BigInt> m = {
    'totalWagered': BigInt.zero,
    'totalBurned': BigInt.zero,
    'totalAirdropped': BigInt.zero,
    'numberOfRounds': BigInt.zero,
  };

  if (r.isNotEmpty) {
    for (Row row in r) {
      m['totalWagered'] = m['totalWagered']! + BigInt.parse(row[0]);
      m['totalBurned'] = m['totalBurned']! + BigInt.parse(row[1]);
      m['totalAirdropped'] = m['totalAirdropped']! + BigInt.parse(row[2]);
      m['numberOfRounds'] = m['numberOfRounds']! + BigInt.one;
    }
  }
  return m;
}

Future<Map<Address, BigInt>> getLargestBet(String table) async {
  List r = await DatabaseService().conn.query('''
      SELECT address, largestBet
      FROM $table
      ''').toList();

  Map<Address, BigInt> m = {};
  if (r.isNotEmpty) {
    for (Row row in r) {
      m[Address.parse(row[0])] = BigInt.parse(row[1]);
    }
  }
  return m;
}

Future<Map<String, dynamic>> getPlayer(String address) async {
  List r = await DatabaseService().conn.query('''
        SELECT *
        FROM ${Table.players}
        WHERE address = @address;
      ''', {'address': address}).toList();
  if (r.isNotEmpty) {
    final row = r.first;
    return {
      'address': Address.parse(row[0]),
      'numberOfBets': row[1],
      'roundsPlayed': row[2],
      'roundsWon': row[3],
    };
  }
  return {};
}

Future<Map<String, dynamic>> selectPlayerStats(
  String address,
  String table, {
  String column = 'address',
}) async {
  List r = await DatabaseService().conn.query('''
      SELECT * 
      FROM $table 
      WHERE $column = @address;
      ''', {'address': address}).toList();
  if (r.isNotEmpty) {
    final row = r.first;
    return {
      'address': Address.parse(row[0]),
      'betTotal': BigInt.parse(row[1]),
      'largestBet': BigInt.parse(row[2]),
      'wonTotal': BigInt.parse(row[3]),
      'roundsPlayed': row[4],
      'roundsWon': row[5]
    };
  }
  return {};
}

Future<Map<String, dynamic>> selectRound(
    int roundNumber, bool canReturnCurrent) async {
  if (canReturnCurrent) {
    // edge case, current round columns are not populated with valid data
    Map<String, dynamic> currentRound = await getCurrentRoundStatus();
    if (currentRound.isNotEmpty &&
        currentRound['roundNumber'] == roundNumber &&
        currentRound['active']) {
      List r = await DatabaseService().conn.query('''
      SELECT * 
      FROM ${Table.rounds} 
      WHERE roundNumber = @roundNumber;
      ''', {'roundNumber': roundNumber}).toList();
      if (r.isNotEmpty) {
        final row = r.first;
        return {
          'roundNumber': row[0],
          'startHeight': row[1],
          'endHeight': row[2],
          'tokenStandard': TokenStandard.parse(row[3]),
        };
      }
      return {};
    }
  }

  List r = await DatabaseService().conn.query('''
      SELECT * 
      FROM ${Table.rounds} 
      WHERE roundNumber = @roundNumber;
      ''', {'roundNumber': roundNumber}).toList();
  if (r.isNotEmpty) {
    final row = r.first;

    if (row[8] == '0') {
      return {'winner': '0'};
    }
    return {
      'roundNumber': row[0],
      'startHeight': row[1],
      'endHeight': row[2],
      'tokenStandard': TokenStandard.parse(row[3]),
      'hash': Hash.parse(row[4]),
      'seed': BigInt.parse(row[5]),
      'pot': BigInt.parse(row[6]),
      'winningTicket': BigInt.parse(row[7]),
      'winner': Address.parse(row[8]),
      'winnerAmount': BigInt.parse(row[9]),
      'winnerBonus': BigInt.parse(row[10]),
      'burnAmount': BigInt.parse(row[11]),
      'devAmount': BigInt.parse(row[12]),
      'airdropAmount': BigInt.parse(row[13]),
      'airdropRecipients': row[14],
      'bpsBurn': row[15],
      'bpsDev': row[16],
      'bpsAirdrop': row[17],
      'airdropZts': TokenStandard.parse(row[18]),
      'active': row[19],
    };
  }
  return {};
}

Future<Map<Address, BigInt>> selectLeaderboardStats(
  String table,
  String column,
) async {
  List r = await DatabaseService().conn.query('''
      SELECT address, $column
      FROM $table;
      ''').toList();
  Map<Address, BigInt> m = {};
  if (r.isNotEmpty) {
    for (Row row in r) {
      try {
        m[Address.parse(row[0])] = BigInt.parse(row[1]);
      } catch (e) {
        m[Address.parse(row[0])] = BigInt.from(row[1]);
      }
    }
  }
  return m;
}
