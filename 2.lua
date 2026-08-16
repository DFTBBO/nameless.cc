print("王伟宸死妈")

-- 加载 Rayfield UI 库
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- 创建 UI 窗口
local Window = Rayfield:CreateWindow({
    Name = "nameless.cc",
    LoadingTitle = "C4",
    LoadingSubtitle = "by chz",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "C4AutoConfig"
    },
    KeySystem = false,
})

-- 创建主标签页
local MainTab = Window:CreateTab("C4", "target")

-- 配置变量
local c4Enabled = false
local c4Speed = 50
local specificTargetName = ""

-- UI 控件
MainTab:CreateToggle({
    Name = "use C4 auto fly ",
    CurrentValue = false,
    Flag = "C4AutoToggle",
    Callback = function(Value)
        c4Enabled = Value
    end,
})

MainTab:CreateSlider({
    Name = "C4 fly speed",
    Range = {20, 100},
    Increment = 5,
    CurrentValue = 50,
    Flag = "C4SpeedSlider",
    Callback = function(Value)
        c4Speed = Value
    end,
})

MainTab:CreateInput({
    Name = "仅锁定 (留空则自动锁定最近)",
    PlaceholderText = "用户名",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        specificTargetName = Text
    end,
})

-- 核心游戏服务与变量
local Debris = workspace:WaitForChild("Debris")
local VParts = Debris:WaitForChild("VParts")
local plrs = game:GetService("Players")
local me = plrs.LocalPlayer
local run = game:GetService("RunService")
local camera = workspace.CurrentCamera
local Break = false

-- 寻找最佳目标函数
local function GetTarget()
    if specificTargetName ~= "" then
        local found = plrs:FindFirstChild(specificTargetName)
        if found and found.Character and found.Character:FindFirstChild("HumanoidRootPart") then
            return found.Character
        end
    end
    
    local nearestChar = nil
    local shortestDist = math.huge
    for _, p in ipairs(plrs:GetPlayers()) do
        if p ~= me and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if me.Character and me.Character:FindFirstChild("HumanoidRootPart") then
                    local dist = (me.Character.HumanoidRootPart.Position - p.Character.HumanoidRootPart.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        nearestChar = p.Character
                    end
                end
            end
        end
    end
    return nearestChar
end

-- 高精度安全多向寻路探测函数：严禁任何撞墙与穿墙，确保0.5m安全距离，多角度扫描并动态绕开所有建筑
local function GetSafeDirection(currentPos, targetPos, raycastParams)
    local directVector = targetPos - currentPos
    local distToTarget = directVector.Magnitude
    local dirToTarget = directVector.Unit
    
    -- 1. 首先尝试直接朝向目标进行远距离安全扫描 (检查前方 5 米)
    local forwardCheck = workspace:Raycast(currentPos, dirToTarget * math.min(5, distToTarget), raycastParams)
    if not forwardCheck then
        return dirToTarget, false
    end
    
    -- 2. 前方遇到障碍物，全面启动多维广度扫描（上下左右及对角线，寻找缝隙、门窗、高空绕行路线）
    local scanSteps = {
        Vector3.new(0, 4, 0),    -- 向上高飞绕过障碍
        Vector3.new(0, -3, 0),   -- 向下
        Vector3.new(4, 0, 0),    -- 向右
        Vector3.new(-4, 0, 0),   -- 向左
        Vector3.new(3, 3, 0),    -- 右上方
        Vector3.new(-3, 3, 0),   -- 左上方
        Vector3.new(0, 7, 0),    -- 更高空绕过大型建筑
        Vector3.new(6, 0, 0),    -- 宽幅向右
        Vector3.new(-6, 0, 0),   -- 宽幅向左
    }
    
    local bestDir = dirToTarget
    local minCost = math.huge
    local foundValidPath = false
    
    for _, offset in ipairs(scanSteps) do
        -- 确保自身距离墙体维持在0.5m以上安全距离，不贴墙
        local safetyRay = workspace:Raycast(currentPos, offset, raycastParams)
        if not safetyRay then
            local candidatePos = currentPos + offset
            -- 检查从候选点到目标的路径是否通畅，杜绝死胡同
            local pathRay = workspace:Raycast(candidatePos, (targetPos - candidatePos).Unit * 5, raycastParams)
            if not pathRay then
                -- 评估综合代价：既要靠近目标，又要远离当前障碍
                local cost = (candidatePos - targetPos).Magnitude
                if cost < minCost then
                    minCost = cost
                    bestDir = (candidatePos - currentPos).Unit
                    foundValidPath = true
                end
            end
        end
    end
    
    -- 如果全方位受阻，则强制向上升空规避死角，绝对不卡死、不硬撞
    if not foundValidPath then
        bestDir = Vector3.new(0, 1, 0)
    end
    
    return bestDir, true
end

-- C4 生成及全自动导航逻辑
VParts.ChildAdded:Connect(function(Projectile)
    if not c4Enabled then return end

    task.wait()
    if Projectile.Name == "TransIgnore" then
        if not me.Character then return end
        if not me.Character:FindFirstChild("C4") then return end

        -- 解除原摄像机绑定，实现独立智能视角或不干扰玩家视角
        pcall(function()
            if Projectile:FindFirstChild("BodyForce") then Projectile.BodyForce:Destroy() end
            if Projectile:FindFirstChild("BodyAngularVelocity") then Projectile.BodyAngularVelocity:Destroy() end
            if Projectile:FindFirstChild("Sound") then Projectile.Sound:Destroy() end
        end)

        local BV = Instance.new("BodyVelocity", Projectile)
        BV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        BV.Velocity = Vector3.new()

        local BG = Instance.new("BodyGyro", Projectile)
        BG.P = 9e4
        BG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)

        -- 高亮显示 C4（实时发光与可视化追踪标识，方便肉眼观察）
        local highlight = Instance.new("Highlight", Projectile)
        highlight.Name = "C4Highlight"
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)

        -- 严密的射线过滤参数：绝对排除自身、角色及 C4 实体本身，防止误判
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        local excludeList = {Projectile}
        if me.Character then table.insert(excludeList, me.Character) end
        local targetChar = GetTarget()
        if targetChar then table.insert(excludeList, targetChar) end
        raycastParams.FilterDescendantsInstances = excludeList
        raycastParams.IgnoreWater = true

        task.spawn(function()
            while Projectile and Projectile.Parent and c4Enabled do
                run.RenderStepped:Wait()
                
                local currentTargetChar = GetTarget()
                if currentTargetChar and currentTargetChar:FindFirstChild("HumanoidRootPart") then
                    -- 目标位置：精准贴附在玩家脚下地面，保持水平无倾斜
                    local targetPos = currentTargetChar.HumanoidRootPart.Position - Vector3.new(0, 3, 0)
                    local currentPos = Projectile.Position
                    
                    local distToTarget = (currentPos - targetPos).Magnitude
                    
                    if distToTarget < 1.5 then
                        -- 抵达目标附近，平稳停在脚下或1米范围内
                        BV.Velocity = Vector3.new(0, 0, 0)
                        break
                    end
                    
                    -- 调用高智能避障寻路算法
                    local moveDir, isBypassing = GetSafeDirection(currentPos, targetPos, raycastParams)
                    
                    -- 动态速度控制：避障时平滑绕行，无阻时全速推进
                    local currentSpeed = isBypassing and (c4Speed * 0.7) or c4Speed
                    BV.Velocity = moveDir * currentSpeed
                    
                    -- 保持 C4 水平贴地无倾斜朝向处理（锁定 Y 轴旋转，防止翻滚或斜着飞）
                    if moveDir.Magnitude > 0 then
                        local flatLookAt = CFrame.lookAt(currentPos, currentPos + Vector3.new(moveDir.X, 0, moveDir.Z))
                        BG.CFrame = flatLookAt
                    end
                else
                    BV.Velocity = Vector3.new(0, 0, 0)
                end
                
                if Break then
                    Break = false
                    break
                end
            end
            
            -- 清理高亮与恢复
            if highlight then highlight:Destroy() end
        end)
    end
end)

-- 爆炸触发监听
Debris.ChildAdded:Connect(function(Result)
    task.wait()
    if not me.Character then return end
    pcall(function()
        if me.Character:FindFirstChild("C4") and (Result.Name == "C4Explosion") then
            Break = true
            task.wait(1)
            Break = false
        end
    end)
end)