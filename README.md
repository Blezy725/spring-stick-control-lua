# ArduPilot Lua: Virtual Spring Control

ArduPilotのLuaスクリプト学習の一環として作成した、仮想ばね（Spring）制御の練習用コードです。

## Overview
このスクリプトは、機体が「目に見えないばね」で基準点に繋がれているような挙動をシミュレートします。

- **基準点（Anchor）**: スイッチをONにした瞬間の座標を保持。
- **復元力**: 基準点からの距離に応じて、中心へ引き戻す速度指令（`set_target_velocity_NED`）を生成。
- **直感的な操作**: パイロットのスティック入力（Body系）を現在のYaw角でWorld系に変換し、復元力と合算。

## Features
- **Hybrid Control**: 復元力は世界座標（World NED）、操作は機体座標（Body NED）で計算し、安定性と直感的な操作を両立。
- **Safety**: 
    - Loiterモード時のみ発動可能。
    - スイッチOFF、または手動のモード変更で即座に制御を中断。
    - モード遷移時のチャタリング防止ロジックを搭載。

## Usage
1. `scripts/spring_control.lua` をフライトコントローラーのSDカード内 `APM/scripts` フォルダに配置。
2. `SCR_ENABLE = 1` を設定。
3. 送信機の Ch6 (デフォルト) で発動。

## Disclaimer
このコードは学習および練習用です。実機での使用は、SITL（シミュレーター）での十分な検証後、安全な環境で行ってください。