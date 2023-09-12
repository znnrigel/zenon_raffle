import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../variables/global.dart';

Future<void> initZenon() async {
  await znnClient.wsClient.initialize(Config.ws, retry: false);
  await znnClient.ledger.getFrontierMomentum().then((value) {
    chainId = value.chainIdentifier.toInt();
  });
  if (znnClient.wsClient.status().name == 'running') {
    logger.log(
        Level.INFO, 'Connected to node: ${Config.ws} with chainId: $chainId');
    await unlockWallet();
    await initVars();
  }
}

Future<void> unlockWallet() async {
  File keyStoreFile =
      File(path.join(znnDefaultWalletDirectory.path, Config.keystore));
  keyStore = await znnClient.keyStoreManager
      .readKeyStore(Config.passphrase, keyStoreFile);
  znnClient.defaultKeyStore = keyStore;
  znnClient.keyStoreManager.setKeyStore(keyStore);
  znnClient.defaultKeyStorePath = keyStoreFile;
  znnClient.defaultKeyPair = znnClient.defaultKeyStore!.getKeyPair();
  Address address = (await znnClient.defaultKeyPair!.address)!;
  logger.log(Level.INFO, 'Unlocked address: $address');
}

Future<void> initVars() async {
  List<TokenStandard> supportedTokens = [znnZts, qsrZts, ppZts];
  for (TokenStandard zts in supportedTokens) {
    Token t = (await znnClient.embedded.token.getByZts(zts))!;
    tokens[t.tokenStandard] = t;
  }
}

bool isAddress(String address) {
  try {
    Address.parse(address);
    return true;
  } catch (e) {
    return false;
  }
}

Future<int> frontierMomentum() async =>
    (await znnClient.ledger.getFrontierMomentum()).height;

Future<AccountBlockList> unreceivedTransactions() async =>
    await znnClient.ledger.getUnreceivedBlocksByAddress(Config.addressPot,
        pageIndex: 0, pageSize: memoryPoolPageSize);

Future<List<AccountBlock>> allUnreceivedTransactions() async {
  List<AccountBlock> list = [];

  // Can only query up to 500 unreceived at a time
  for (int i = 0; i < 10; i++) {
    AccountBlockList currentList = await znnClient.ledger
        .getUnreceivedBlocksByAddress(Config.addressPot,
            pageIndex: i, pageSize: memoryPoolPageSize);

    try {
      currentList.list?.forEach((element) {
        list.add(element);
      });
      if (currentList.count! < memoryPoolPageSize) {
        return list;
      }
    } catch (e) {
      logger.log(Level.WARNING, 'allUnreceivedTransactions(): $e');
      break;
    }
  }
  return list;
}

Future<BigInt> potSum(List<AccountBlock> bets) async {
  BigInt pot = BigInt.zero;

  for (var block in bets) {
    pot += block.amount;
  }
  return pot;
}

Future<void> receiveAll(List<AccountBlock> bets) async {
  for (var block in bets) {
    try {
      await receiveTx(block.hash);
    } catch (e) {
      // try/catch to mitigate "JSON-RPC error -32000: account-block previous block is missing"
      logger.log(Level.WARNING, 'receiveAll(): ${block.hash} || $e');
    }
  }
  logger.log(Level.FINE, 'receiveAll(): Received ${bets.length} bets');
}

Future<bool> distributePot(Address winner, Map<String, dynamic> results) async {
  logger.log(Level.INFO,
      'Distributing pot: ${AmountUtils.addDecimals(raffle.pot, raffle.token.decimals)} ${raffle.token.symbol}');

  if (!(await hasBalance(
      Config.addressPot, raffle.token.tokenStandard, raffle.pot))) {
    logger.log(Level.SEVERE, 'Balance error!!');
    raffleServiceEnabled = false;
    return false;
  }

  if (results['burnAmount']! != BigInt.zero) {
    logger.log(Level.FINE,
        'Burning ${AmountUtils.addDecimals(results['burnAmount']!, raffle.token.decimals)} ${raffle.token.symbol}');
    await burn(results['burnAmount']!);
  }

  if (results['devAmount']! != BigInt.zero) {
    logger.log(Level.FINE,
        'Dev: ${AmountUtils.addDecimals(results['devAmount']!, raffle.token.decimals)} ${raffle.token.symbol}');
    await sendTx(AccountBlockTemplate.send(
        Config.addressDev, raffle.token.tokenStandard, results['devAmount']!));
  }

  if (results['airdropAmount']! != BigInt.zero) {
    logger.log(Level.FINE,
        'Airdrop: ${AmountUtils.addDecimals(results['airdropAmount']!, raffle.token.decimals)} ${raffle.token.symbol} (Total: ${AmountUtils.addDecimals(results['airdropTotal']!, raffle.token.decimals)})');
    for (String recipient in snapshotVars['holders']) {
      // try/catch and while used to mitigate "JSON-RPC error -32000: account-block previous block is missing"
      // should not cause an infinite loop
      bool complete = false;
      while (!complete) {
        try {
          await sendTx(AccountBlockTemplate.send(Address.parse(recipient),
              raffle.token.tokenStandard, results['airdropAmount']!));
          complete = true;
        } catch (e) {
          logger.log(Level.WARNING, 'distributePot(): airdrop');
        }
      }
    }
  }

  BigInt winnerAmount = results['winnerAmount']!;

  // In case the pot receives airdrops, reward the round winner with those as well
  AccountInfo info =
      await znnClient.ledger.getAccountInfoByAddress(Config.addressPot);
  for (BalanceInfoListItem entry in info.balanceInfoList!) {
    if (entry.token!.tokenStandard.toString() ==
        raffle.token.tokenStandard.toString()) {
      if (entry.balance! > winnerAmount) {
        logger.log(Level.FINE,
            'Winner is receiving an airdrop bonus of ${AmountUtils.addDecimals(entry.balance! - winnerAmount, raffle.token.decimals)} ${raffle.token.symbol}');
        raffle.bonus = entry.balance! - winnerAmount;
        winnerAmount = entry.balance!;
      }
    }
  }

  logger.log(Level.FINE,
      'Winner: ${AmountUtils.addDecimals(winnerAmount, raffle.token.decimals)} ${raffle.token.symbol}');
  await sendTx(AccountBlockTemplate.send(
      winner, raffle.token.tokenStandard, winnerAmount));

  return true;
}

Future<bool> hasBalance(
    Address address, TokenStandard tokenStandard, BigInt amount) async {
  AccountInfo info = await znnClient.ledger.getAccountInfoByAddress(address);
  bool ok = true;
  bool found = false;

  if (amount < BigInt.zero) {
    return found;
  }

  for (BalanceInfoListItem entry in info.balanceInfoList!) {
    if (entry.token!.tokenStandard.toString() == tokenStandard.toString()) {
      if (entry.balance! < amount) {
        if (entry.balance == BigInt.zero) {
          logger.log(Level.WARNING,
              'Error! $address does not have any ${entry.token!.symbol}');
        } else {
          logger.log(Level.WARNING,
              'Error! $address only has ${AmountUtils.addDecimals(entry.balance!, entry.token!.decimals)} ${entry.token!.symbol} tokens');
        }
        ok = false;
        return false;
      }
      found = true;
    }
  }

  if (!found) {
    return found;
  }
  return ok;
}

Future<void> refundTx(List<AccountBlock> refunds) async {
  if (refunds.isNotEmpty) {
    for (AccountBlock block in refunds) {
      Address recipient = block.address;
      BigInt amount = block.amount;
      TokenStandard tokenStandard = block.tokenStandard;

      await receiveTx(block.hash);
      if (recipient != Config.addressPot) {
        await sendTx(
            AccountBlockTemplate.send(recipient, tokenStandard, amount));
      }

      int decimals = 0;
      if (tokenStandard == znnZts || tokenStandard == qsrZts) {
        decimals = coinDecimals;
      }

      logger.log(Level.FINE,
          'Refunded ${recipient.toString()} ${AmountUtils.addDecimals(amount, decimals)} ${tokenStandard.toString()}');
    }
  }
}

Future<void> burn(BigInt amount) async {
  // if token == znn or qsr -> donate to az
  // if token == ppZts -> burn
  // do not burn any other tokens yet

  if (raffle.token.tokenStandard == znnZts ||
      raffle.token.tokenStandard == qsrZts) {
    await sendTx(znnClient.embedded.accelerator
        .donate(amount, raffle.token.tokenStandard));
    logger.log(Level.FINE,
        'Donating ${AmountUtils.addDecimals(amount, coinDecimals)} ${raffle.token.symbol} to Accelerator-Z ...');
    return;
  }

  if (raffle.token.tokenStandard == ppZts) {
    await sendTx(znnClient.embedded.token.burnToken(ppZts, amount));
    logger.log(Level.FINE,
        'Burning ${AmountUtils.addDecimals(amount, 0)} ${raffle.token.symbol} ...');
    return;
  }

  logger.log(Level.FINE, 'burn(): Did not burn any tokens');
  return;
}

Future<Hash> getMomentumHash(int height) async =>
    (await znnClient.ledger.getMomentumsByHeight(height, 1)).list.single.hash;

// If anyone decides to send infinite transactions to the potAddress
// We can attempt to mitigate DOS by proactively dealing with these
Future<void> antiDos() async {
  List<AccountBlock> unreceivedTx = await allUnreceivedTransactions();
  if (unreceivedTx.isNotEmpty) {
    for (AccountBlock block in unreceivedTx) {
      BigInt amount = block.amount;
      TokenStandard tokenStandard = block.tokenStandard;

      if (amount == BigInt.zero ||
          tokenStandard != raffle.token.tokenStandard) {
        await receiveTx(block.hash);
      }
    }
  }
}

Future<List<Momentum>> getAllMomentums(int startHeight, int endHeight) async {
  List<Momentum> list = [];

  int count = endHeight - startHeight;
  while (count > 0) {
    logger.log(Level.FINER, 'getAllMomentums(): $count remaining...');
    if (count > rpcMaxPageSize) {
      (await znnClient.ledger.getMomentumsByHeight(startHeight, rpcMaxPageSize))
          .list
          .forEach((momentum) {
        list.add(momentum);
      });
      startHeight += rpcMaxPageSize;
      count -= rpcMaxPageSize;
    } else {
      (await znnClient.ledger.getMomentumsByHeight(startHeight, count))
          .list
          .forEach((momentum) {
        list.add(momentum);
      });
      count = 0;
    }
  }
  return list;
}

// Purpose: to mitigate errors like
// JSON-RPC error -32000: account-block previous block is missing
// May not solve anything...
Future<void> sendTx(AccountBlockTemplate template) async {
  await znnClient.send(template);
  await Future.delayed(const Duration(milliseconds: 1000));
}

Future<void> receiveTx(Hash hash) async {
  await znnClient.send(AccountBlockTemplate.receive(hash));
  await Future.delayed(const Duration(milliseconds: 1000));
}
