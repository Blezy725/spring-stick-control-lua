--[[
  Spring Control Script (Final Production Version)
  - 制御系：World NED（アンカー維持の安定性）
  - 操作系：Body NED（機体基準の直感操作）
  - 安全機能：モード遷移ガード、RC断フェイルセーフ優先、GPS/APIエラー回避
--]]

local RC_CH      = 6
local THRESHOLD  = 1600
local K_SPRING   = 0.25  -- ヌルっと戻るための設定（0.2〜0.5で調整）
local MAX_VEL    = 3.0   -- ヌルっと戻るための最高速度制限 (m/s)
local STICK_SCL  = 3.0   -- スティック操作の感度 (m/s)

local MODE_LOITER = 5
local MODE_GUIDED = 4

-- 状態管理
local active = false
local anchor_pos = nil
local last_gps_msg_ms = 0
local activation_time_ms = 0

-- RCMAPの自動取得 (モード1/2対応)
local CH_ROLL  = param:get('RCMAP_ROLL') or 1
local CH_PITCH = param:get('RCMAP_PITCH') or 2

function update()
    local rc_val = rc:get_pwm(RC_CH)
    local current_mode = vehicle:get_mode()
    local loc = ahrs:get_location()
    local now = millis()

    local rc_connected = (rc_val ~= nil)
    local switch_is_hi = (rc_connected and rc_val > THRESHOLD)

    -- 1. 発動ロジック
    if switch_is_hi and not active and current_mode == MODE_LOITER then
        if loc then
            if vehicle:set_mode(MODE_GUIDED) then
                anchor_pos = loc:copy()
                active = true
                activation_time_ms = now
                gcs:send_text(4, ">>> SPRING MODE: ON <<<")
            end
        elseif (now - last_gps_msg_ms > 5000) then
            gcs:send_text(3, "SPRING: GPS NOT READY")
            last_gps_msg_ms = now
        end
    end

    -- 2. 実行・解除ロジック
    if active then
        -- モード切り替え直後の判定猶予(500ms)
        local transition_done = (now - activation_time_ms > 500)
        
        -- 条件：スイッチが切られた、または（猶予期間後に）モードがGUIDED以外になった
        if not switch_is_hi or (transition_done and current_mode ~= MODE_GUIDED) then
            if not switch_is_hi and current_mode == MODE_GUIDED then
                vehicle:set_mode(MODE_LOITER)
                gcs:send_text(4, ">>> SPRING MODE: OFF (Loiter) <<<")
            else
                gcs:send_text(4, ">>> SPRING MODE: ABORTED <<<")
            end
            active = false
            anchor_pos = nil
        else
            -- 速度制御実行
            if current_mode == MODE_GUIDED and loc and anchor_pos then
                -- A. ばねの復元力 (World NED系)
                local diff_world = loc:get_distance_NE(anchor_pos)
                local spring_vel_n = diff_world:x() * K_SPRING
                local spring_vel_e = diff_world:y() * K_SPRING

                -- B. スティック操作量 (Body系)
                local yaw = ahrs:get_yaw()
                local pitch_raw = (rc:get_pwm(CH_PITCH) or 1500)
                local roll_raw  = (rc:get_pwm(CH_ROLL) or 1500)
                
                -- スティック入力を -1.0 〜 1.0 に正規化 (ピッチ前進がプラス)
                local stick_fwd  = -(pitch_raw - 1500) / 500.0
                local stick_left = (roll_raw - 1500) / 500.0

                -- C. スティック操作量をWorld系(北・東)へ回転変換
                local stick_vel_n = (stick_fwd * math.cos(yaw) - stick_left * math.sin(yaw)) * STICK_SCL
                local stick_vel_e = (stick_fwd * math.sin(yaw) + stick_left * math.cos(yaw)) * STICK_SCL

                -- D. 合算
                local target_vel_n = spring_vel_n + stick_vel_n
                local target_vel_e = spring_vel_e + stick_vel_e
                
                -- 合成速度リミッター (ベクトルの長さで制限)
                local mag = math.sqrt(target_vel_n^2 + target_vel_e^2)
                if mag > MAX_VEL then
                    local scale = MAX_VEL / mag
                    target_vel_n = target_vel_n * scale
                    target_vel_e = target_vel_e * scale
                end

                -- 指令値の送信 (Vector3fオブジェクトの安全な生成)
                local target_v = Vector3f()
                target_v:x(target_vel_n)
                target_v:y(target_vel_e)
                target_v:z(0)
                vehicle:set_target_velocity_NED(target_v)
            end
        end
    end

    return update, 20
end

return update()