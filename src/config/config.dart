import 'package:settings_yaml/settings_yaml.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

class Config {
  static String _databaseAddress = '127.0.0.1';
  static int _databasePort = 5432;
  static late String _databaseName;
  static late String _databaseUsername;
  static late String _databasePassword;

  static late String _ws;
  static late String _keystore;
  static late String _passphrase;

  static late Address _addressDev;
  static late Address _addressPot;
  static late TokenStandard _airdropZts;
  static late int roundDuration;
  static late int bpsBurn;
  static late int bpsDev;
  static late int bpsAirdrop;

  static late String _tgBotKey;
  static late List<dynamic> _admins;
  static late int _channel; // telegram announcement channel

  static String get databaseAddress => _databaseAddress;
  static int get databasePort => _databasePort;
  static String get databaseName => _databaseName;
  static String get databaseUsername => _databaseUsername;
  static String get databasePassword => _databasePassword;

  static String get ws => _ws;
  static String get keystore => _keystore;
  static String get passphrase => _passphrase;

  static Address get addressDev => _addressDev;
  static Address get addressPot => _addressPot;
  static TokenStandard get airdropZts => _airdropZts;

  static String get tgBotKey => _tgBotKey;
  static List<dynamic> get admins => _admins;
  static int get channel => _channel;

  static void load() {
    final settings = SettingsYaml.load(pathToSettings: './config.yaml');

    _databaseAddress = settings['database_address'] as String;
    _databasePort = settings['database_port'] as int;
    _databaseName = settings['database_name'] as String;
    _databaseUsername = settings['database_username'] as String;
    _databasePassword = settings['database_password'] as String;

    _ws = settings['secrets']['zenon']['ws'] as String;
    _keystore = settings['secrets']['zenon']['keystore'] as String;
    _passphrase = settings['secrets']['zenon']['passphrase'] as String;

    _addressDev = Address.parse(settings['raffle']['address_dev'] as String);
    _addressPot = Address.parse(settings['raffle']['address_pot'] as String);
    _airdropZts =
        TokenStandard.parse(settings['raffle']['airdrop_zts'] as String);
    roundDuration = settings['raffle']['round_duration'] as int;
    bpsBurn = settings['raffle']['bps_burn'] as int;
    bpsDev = settings['raffle']['bps_dev'] as int;
    bpsAirdrop = settings['raffle']['bps_airdrop'] as int;

    _tgBotKey = settings['secrets']['tg_bot_key'] as String;
    _admins = settings['admins'] as List<dynamic>;
    _channel = settings['channel'] as int;
  }
}
