import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgresql2/postgresql.dart';

import '../config/config.dart';
import '../variables/global.dart';

export 'database_select_queries.dart';
export 'database_update_queries.dart';

class Table {
  static String get players => 'players';
  static String get rounds => 'rounds';
  static String get bets => 'bets';
  static String get znnStats => 'znnStats';
  static String get qsrStats => 'qsrStats';
  static String get ppStats => 'ppStats';
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }
  DatabaseService._internal();

  Connection get conn => _conn;
  late final Connection _conn;

  final _uri =
      'postgres://${Config.databaseUsername}:${Config.databasePassword}@${Config.databaseAddress}:${Config.databasePort}/${Config.databaseName}';

  init() async {
    _conn = await connect(_uri);
    logger.log(Level.INFO,
        'Connected to database: postgres://${Config.databaseUsername}:<redacted>@${Config.databaseAddress}:${Config.databasePort}/${Config.databaseName}');
    //await resetTables();
    await initTables();
  }

  dispose() {
    logger.log(Level.INFO, 'database_service.dispose()');
    _conn.close();
  }

  Future<void> initTables() async {
    try {
      await _conn.runInTransaction(() async {
        final createPlayersTable = '''
        CREATE TABLE IF NOT EXISTS ${Table.players} (
          address text PRIMARY KEY,
          numberOfBets int NOT NULL,
          roundsPlayed int NOT NULL,
          roundsWon int NOT NULL
        );
        ''';

        final createRoundsTable = '''
        CREATE TABLE IF NOT EXISTS ${Table.rounds} (
          roundNumber serial PRIMARY KEY,
          startHeight int NOT NULL,
          endHeight int NOT NULL,
          tokenStandard text NOT NULL,
          hash text NOT NULL,
          seed text NOT NULL,
          pot text NOT NULL,
          winningTicket text NOT NULL,
          winner text NOT NULL REFERENCES players(address),
          winnerAmount text NOT NULL,
          winnerBonus text NOT NULL,
          burnAmount text NOT NULL,
          devAmount text NOT NULL,
          airdropAmount text NOT NULL,
          airdropRecipients int NOT NULL,
          bpsBurn int NOT NULL,
          bpsDev int NOT NULL,
          bpsAirdrop int NOT NULL,
          airdropZts text NOT NULL
        );
        ''';

        final createBetsTable = '''
        CREATE TABLE IF NOT EXISTS ${Table.bets} (
          txHash text PRIMARY KEY,
          address text NOT NULL REFERENCES players(address),
          roundNumber int NOT NULL REFERENCES rounds(roundNumber),
          tokenStandard text NOT NULL,
          amount text NOT NULL,
          momentumHeight int NOT NULL
        );
        ''';

        final createZnnStatsTable = '''
        CREATE TABLE IF NOT EXISTS ${Table.znnStats} (
          address text PRIMARY KEY REFERENCES players(address),
          betTotal text NOT NULL,
          largestBet text NOT NULL,
          wonTotal text NOT NULL,
          roundsPlayed int NOT NULL,
          roundsWon int NOT NULL
        );
        ''';

        final createQsrStatsTable =
            'CREATE TABLE IF NOT EXISTS ${Table.qsrStats} (LIKE ${Table.znnStats} INCLUDING all);';
        final createPpStatsTable =
            'CREATE TABLE IF NOT EXISTS ${Table.ppStats} (LIKE ${Table.znnStats} INCLUDING all);';

        await _conn.query(createPlayersTable).toList();
        await _conn.query(createRoundsTable).toList();
        await _conn.query(createBetsTable).toList();
        await _conn.query(createZnnStatsTable).toList();
        await _conn.query(createQsrStatsTable).toList();
        await _conn.query(createPpStatsTable).toList();

        logger.log(Level.FINE, 'initTables() completed successfully');
      });
    } catch (e, stackTrace) {
      logger.log(Level.SEVERE, 'initTables()', e, stackTrace);
      dispose();
      exit(1);
    }
  }

  Future<void> resetTables() async {
    try {
      await _conn.runInTransaction(() async {
        await _conn.query('DROP TABLE ${Table.ppStats};').toList();
        await _conn.query('DROP TABLE ${Table.qsrStats};').toList();
        await _conn.query('DROP TABLE ${Table.znnStats};').toList();
        await _conn.query('DROP TABLE ${Table.bets};').toList();
        await _conn.query('DROP TABLE ${Table.rounds};').toList();
        await _conn.query('DROP TABLE ${Table.players};').toList();

        logger.log(Level.FINE, 'resetTables() completed successfully');
      });
    } catch (e, stackTrace) {
      logger.log(Level.SEVERE, 'resetTables()', e, stackTrace);
      dispose();
      exit(1);
    }
  }
}
