import 'package:logging/logging.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../database/database_service.dart';
import '../raffle.dart';

final Logger logger = Logger('zenonraffle');

final Zenon znnClient = Zenon();
late final KeyStore keyStore;

Map<TokenStandard, Token> tokens = {};

late dynamic snapshotVars;

bool raffleServiceEnabled = true;
late Raffle raffle;

final raffleChannel = 'https://t.me/zenonraffle';
final docsLink = 'https://zenon-raffle.gitbook.io/docs/';

late final DatabaseService db;

final int momentumTime = 10; // seconds

TokenStandard ppZts = TokenStandard.parse('zts1hz3ys62vnc8tdajnwrz6pp');
