import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../variables/global.dart';
import '../functions/zenon_functions.dart';

const String snapshotFile = './src/indexer/snapshot.json';
bool firstSnapshot = false;

// Opted to use a .json file instead of multiple db tables
// Maybe I'll change this later

initIndexer() async {
  Map snapshotFile = await readSnapshot();

  int height = 0;
  TokenStandard tokenStandard = Config.airdropZts;
  List<String> holders = [];
  List<String> pendingHolders = [];

  if (snapshotFile.isNotEmpty) {
    height = snapshotFile['height'];
    tokenStandard = TokenStandard.parse(snapshotFile['tokenstandard']);

    logger.log(
        Level.FINE, '[indexer] initIndexer(): updating index from $height');

    for (var h in snapshotFile['holders']) {
      holders.add(h);
    }

    for (var h in snapshotFile['pendingHolders']) {
      pendingHolders.add(h);
    }
  } else {
    print(
        '\nsnapshot.json not found. The indexer must generate this file to proceed.');
    print(
        'The greater the indexing history, the longer this process will take.');
    bool invalid = true;
    while (invalid) {
      try {
        print('Enter the starting momentum height for the indexing: ');
        height = int.parse(stdin.readLineSync()!);
        invalid = false;
      } catch (e) {/* no response */}
      ;
    }
    firstSnapshot = true;
    logger.log(Level.INFO,
        '[indexer] initIndexer(): creating snapshot for ${tokenStandard.toString()}, starting at height $height...');
  }

  snapshotVars = {
    "height": height,
    "tokenstandard": tokenStandard.toString(),
    "holders": holders,
    "pendingHolders": pendingHolders
  };

  int currentHeight = await frontierMomentum();
  await updateCurrentHolders(currentHeight);

  await backupCurrentValues(snapshotVars);
}

Future<Map<String, dynamic>> readSnapshot() async {
  try {
    return jsonDecode(await File(snapshotFile).readAsString());
  } catch (e) {
    return {};
  }
}

Future<void> backupCurrentValues(Map<String, dynamic> json) async {
  JsonEncoder encoder = JsonEncoder.withIndent('  ');
  String prettyprint = encoder.convert(json);
  //print(prettyprint);
  File(snapshotFile).writeAsStringSync(prettyprint);
}

Future<void> updateCurrentHolders(int endHeight) async {
  List<Momentum> momentums =
      await getAllMomentums(snapshotVars['height'], endHeight);
  List<Address> senderAddresses = [];
  List<Address> recipientAddresses = [];

  TokenStandard holdingToken =
      TokenStandard.parse(snapshotVars['tokenstandard']);

  // Parse all momentum since last snapshot height for transactions with snapshotVars['tokenstandard'] tokens
  // - Senders immediately have their accounts updated
  // - Recipients need to acknowledge the tx to update their accounts
  // -- unreceived tx do not count in the airdrop
  for (Momentum m in momentums) {
    if (firstSnapshot && m.height % 10000 == 0) {
      logger.log(
          Level.INFO, '[indexer] momentum parsing progress: ${m.height}');
    }
    if (m.content.isNotEmpty) {
      DetailedMomentum dm =
          (await znnClient.ledger.getDetailedMomentumsByHeight(m.height, 1))
              .list!
              .single;

      for (AccountBlock block in dm.blocks) {
        if (block.tokenStandard == holdingToken) {
          logger.log(Level.FINE,
              '[indexer] updateCurrentHolders(): from: ${block.address} --> to: ${block.toAddress}');
          senderAddresses.add(block.address);
          recipientAddresses.add(block.toAddress);
        }
      }
    }
  }
  senderAddresses = senderAddresses.toSet().toList();
  for (Address a in senderAddresses) {
    if (!(await hasBalance(a, holdingToken, BigInt.one))) {
      snapshotVars['holders'].remove(a.toString());
      logger.log(Level.FINE,
          '[indexer] updateCurrentHolders(): $a no longer has $holdingToken');
    } else {
      snapshotVars['holders'].add(a.toString());
      logger.log(
          Level.FINE, '[indexer] updateCurrentHolders(): $a has $holdingToken');
    }
  }

  // recipient addresses and known pendingHolders are checked for completed holdingToken transfers
  for (String ph in snapshotVars['pendingHolders']) {
    recipientAddresses.add(Address.parse(ph));
  }

  for (Address a in List.from(recipientAddresses)) {
    AccountBlockList unreceived = await znnClient.ledger
        .getUnreceivedBlocksByAddress(a, pageIndex: 0, pageSize: 5);
    bool hasUnreceived = false;

    if (unreceived.count! > 0) {
      for (AccountBlock b in unreceived.list!) {
        if (b.tokenStandard == holdingToken) {
          hasUnreceived = true;
        }
      }
    }

    var unconfirmed = await znnClient.ledger
        .getUnconfirmedBlocksByAddress(a, pageIndex: 0, pageSize: 5);
    bool hasUnconfirmed = false;

    if (unconfirmed.count! > 0) {
      for (AccountBlock b in unconfirmed.list!) {
        if (b.tokenStandard == holdingToken) {
          hasUnconfirmed = true;
        }
      }
    }

    if (!hasUnreceived && !hasUnconfirmed) {
      snapshotVars['pendingHolders'].remove(a.toString());
    } else {
      snapshotVars['pendingHolders'].add(a.toString());
    }
  }
  snapshotVars['pendingHolders'] =
      snapshotVars['pendingHolders'].toSet().toList();

  recipientAddresses = recipientAddresses.toSet().toList();
  for (Address a in recipientAddresses) {
    if (!(await hasBalance(a, holdingToken, BigInt.one))) {
      snapshotVars['holders'].remove(a.toString());
      logger.log(Level.FINE,
          '[indexer] updateCurrentHolders(): $a has not claimed their $holdingToken');
    } else {
      snapshotVars['holders'].add(a.toString());
      logger.log(Level.FINE,
          '[indexer] updateCurrentHolders(): $a has a $holdingToken');
    }
  }

  snapshotVars['holders'] = snapshotVars['holders'].toSet().toList();
  //print('current airdrop holders = ${snapshotVars['holders']}');

  snapshotVars['height'] = endHeight;
}
