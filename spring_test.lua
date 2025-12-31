--[[
  Spring Control Script (Final API Fix)
--]]

local RC_CH      = 6
local THRESHOLD  = 1600
local K_SPRING   = 0.5
local MAX_VEL    = 5.0
local STICK_SCL  = 3.0

local MODE_LOITER = 5
local MODE_GUIDED = 4

local active = false
local anchor_pos = nil
local last_gps_msg_ms = 0
local activation_time_ms = 0

local CH_ROLL  = param:get('RCMAP_ROLL') or 1
local CH_PITCH = param:get('RCMAP_PITCH') or 2

function update()
    local rc_val = rc:get_pwm(RC_CH)
    local current_mode = vehicle:get_mode()
    local loc = ahrs:get_location()
    local now = millis()

    local rc_connected = (rc_val ~= nil)
    local switch_is_hi = (rc_connected and rc_val > THRESHOLD)

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

    if active then
        local transition_done = (now - activation_time_ms > 500)
        
        if not switch_is_hi or (transition_done and current_mode ~= MODE_GUIDED) then
            if not switch_is_hi and current_mode == MODE_GUIDED then
                vehicle:set_mode(MODE_LOITER)
                gcs:send_text(4, ">>> SPRING MODE: OFF <<<")
            else
                gcs:send_text(4, ">>> SPRING MODE: ABORTED <<<")
            end
            active = false
            anchor_pos = nil
        else
            if current_mode == MODE_GUIDED and loc and anchor_pos then
                local diff_vec = loc:get_distance_NE(anchor_pos)
                local pitch_raw = (rc:get_pwm(CH_PITCH) or 1500)
                local roll_raw  = (rc:get_pwm(CH_ROLL) or 1500)
                local stick_pitch = (pitch_raw - 1500) / 500.0
                local stick_roll  = (roll_raw - 1500) / 500.0
                
                local target_vel_n = (diff_vec:x() * K_SPRING) + (-stick_pitch * STICK_SCL)
                local target_vel_e = (diff_vec:y() * K_SPRING) + (stick_roll * STICK_SCL)
                
                local mag = math.sqrt(target_vel_n^2 + target_vel_e^2)
                if mag > MAX_VEL then
                    local scale = MAX_VEL / mag
                    target_vel_n = target_vel_n * scale
                    target_vel_e = target_vel_e * scale
                end

                -- 修正箇所: Vector3f.new を明示的に使い、NEDベクトルを作成
                local target_v = Vector3f()
                target_v:x(target_vel_n)
                target_v:y(target_vel_e)
                target_v:z(0)
                
                -- 修正箇所: 引数の渡し方をより安全な形に変更
                vehicle:set_target_velocity_NED(target_v)
            end
        end
    end

    return update, 20
end

return update()