## Zenon Raffle Bot
 
A Telegram bot that runs a daily lottery on NoM.  

Supported ZTS:
* `ZNN` Zenon
* `QSR` Quasar
* `PP`  PlasmaPoints

Telegram: [@zenonrafflebot](https://t.me/zenonrafflebot)  
Announcements:  https://t.me/zenonraffle  
Docs: https://zenon-raffle.gitbook.io/docs/

----

### To get started
#### Prerequisites
You will need the following:
1. Postgres database
2. Telegram bot and channel
3. ZTS for the revenue share

#### Setup
1. ```
   git clone https://github.com/znnrigel/zenon_raffle.git
   cd zenon_raffle
   ```
2. Copy `config.yaml.example` to `config.yaml` and populate the values for the service.
3. ```
   dart pub get
   dart run ./bin/zenonrafflebot.dart
   ```
