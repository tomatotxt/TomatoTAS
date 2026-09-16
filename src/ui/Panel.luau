-- Native Roblox GUI. All engine operations are routed through App's public API.
return function(import,config)
    local Scope=import("core/Scope")
    local Model=import("ui/Model")
    local UIS=game:GetService("UserInputService")
    local RS=game:GetService("RunService")
    local Tween=game:GetService("TweenService")
    local Players=game:GetService("Players")
    local Panel={}
    Panel.__index=Panel
    local W,H=680,620
    local colors={bg=Color3.fromRGB(18,20,25),card=Color3.fromRGB(26,29,35),raised=Color3.fromRGB(34,38,45),
        line=Color3.fromRGB(49,53,62),text=Color3.fromRGB(241,238,232),muted=Color3.fromRGB(146,153,168),
        tomato=Color3.fromRGB(244,106,84),green=Color3.fromRGB(113,204,163),amber=Color3.fromRGB(231,191,120)}
    local function make(class,parent,properties)
        local object=Instance.new(class)
        for key,value in pairs(properties or {}) do object[key]=value end
        object.Parent=parent
        return object
    end
    local function corner(object,radius) make("UICorner",object,{CornerRadius=UDim.new(0,radius or 10)}) end
    local function stroke(object,color) make("UIStroke",object,{Color=color or colors.line,Thickness=1,Transparency=0.15}) end
    local function frame(parent,x,y,w,h,color)
        return make("Frame",parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
            BackgroundColor3=color or colors.card,BorderSizePixel=0})
    end
    local function label(parent,text,x,y,w,h,size,color,font)
        return make("TextLabel",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
            BackgroundTransparency=1,TextColor3=color or colors.text,TextSize=size or 13,
            Font=font or Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd,RichText=false})
    end
    function Panel:Button(parent,text,x,y,w,h,fn,primary,scope)
        scope=scope or self.scope
        local base=if primary then colors.tomato else colors.raised
        local b=make("TextButton",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
            BackgroundColor3=base,BorderSizePixel=0,TextColor3=if primary then colors.bg else colors.text,
            TextSize=13,Font=Enum.Font.GothamMedium,AutoButtonColor=false,TextTruncate=Enum.TextTruncate.AtEnd})
        corner(b,9)
        local entry={object=b,enabled=true,base=base,primary=primary}
        scope:Add(b.Activated:Connect(function()
            if not entry.enabled or scope.dead or self.scope.dead then return end
            task.spawn(function()
                if not entry.enabled or scope.dead or self.scope.dead then return end
                local ok,err=pcall(fn)
                if not ok then self:Notice(tostring(err),"error") end
            end)
        end))
        local tween
        local function animate(color)
            if tween then tween:Cancel() end
            tween=Tween:Create(b,TweenInfo.new(0.12),{BackgroundColor3=color})
            tween:Play()
        end
        scope:Add(b.MouseEnter:Connect(function() if entry.enabled then animate(base:Lerp(colors.text,0.09)) end end))
        scope:Add(b.MouseLeave:Connect(function() animate(base) end))
        scope:Add(function() if tween then tween:Cancel() end end)
        return entry
    end
    function Panel:Enabled(entry,enabled)
        if entry.enabled==enabled then return end
        entry.enabled=enabled
        entry.object.TextTransparency=if enabled then 0 else 0.6
        entry.object.BackgroundTransparency=if enabled then 0 else 0.55
    end
    function Panel:Box(parent,placeholder,text,x,y,w)
        local b=make("TextBox",parent,{Text=text,PlaceholderText=placeholder,Position=UDim2.fromOffset(x,y),
            Size=UDim2.fromOffset(w,38),BackgroundColor3=colors.bg,BorderSizePixel=0,TextColor3=colors.text,
            PlaceholderColor3=colors.muted,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,
            TextXAlignment=Enum.TextXAlignment.Left,MultiLine=false})
        corner(b,9); stroke(b)
        make("UIPadding",b,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)})
        return b
    end
    function Panel:Notice(message,level)
        self.app:Notify(message,level or "info")
    end
    function Panel:Run(fn,ready)
        if self.scope.dead then return end
        if self.app.busy then self:Notice("A map operation is running. Stop can cancel it."); return end
        if ready then
            local reason=self.app:ReadyReason()
            if reason then self:Notice(reason); return end
        end
        self.app:Command(fn)
    end
    function Panel:NewRun()
        if self.app.busy then self:Notice("A map operation is running. Stop can cancel it."); return end
        local reason=self.app:ReadyReason(true)
        if reason then self:Notice(reason); return end
        local tree=self.app.tree
        if tree and (self.confirmTree~=tree or not self.confirmAt or os.clock()-self.confirmAt>4) then
            self.confirmTree=tree; self.confirmAt=os.clock()
            self:Notice("Click New run again within 4 seconds to replace the current run. Save first.","warning")
            return
        end
        self.confirmTree=nil; self.confirmAt=nil
        self:Run(function() self.app:NewRun(); self:Notice("New run ready. Record when you're ready.") end)
    end
    function Panel:Build()
        self.screen=make("ScreenGui",nil,{Name="TomatoTAS_Interface",ResetOnSpawn=false,DisplayOrder=80,
            ZIndexBehavior=Enum.ZIndexBehavior.Sibling,IgnoreGuiInset=false})
        self.scope:Add(self.screen)
        self.surface=make("Frame",self.screen,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
        self.window=frame(self.surface,0,0,W,H,colors.bg)
        self.window.Active=true
        corner(self.window,16); stroke(self.window)
        self.scale=make("UIScale",self.window,{Scale=1})
        local accent=frame(self.window,24,0,84,3,colors.tomato); corner(accent,2)
        self.header=frame(self.window,0,0,W-108,76,colors.bg)
        self.header.BackgroundTransparency=1; self.header.Active=true
        local logo=frame(self.header,24,23,32,32,colors.tomato); corner(logo,16)
        local leaf=frame(self.header,39,18,13,5,colors.green); corner(leaf,3); leaf.Rotation=-25
        label(self.header,"TomatoTAS",68,18,250,27,23,colors.text,Enum.Font.GothamBold)
        label(self.header,"FLOOD ESCAPE 2  /  STUDIO",69,47,310,16,10,colors.muted)
        self.badge=label(self.window,"IDLE",440,27,124,24,11,colors.green,Enum.Font.GothamBold)
        self.badge.TextXAlignment=Enum.TextXAlignment.Right
        self:Button(self.window,"Hide",582,24,46,28,function() self:Toggle(false) end)
        self:Button(self.window,"×",634,24,26,28,function() self.app:Dispatch("Unload") end)
        local hero=frame(self.window,24,82,632,100); corner(hero,12); stroke(hero)
        label(hero,"CURRENT MAP",18,12,350,16,10,colors.muted)
        self.mapLabel=label(hero,"Waiting for map…",18,33,363,28,20,colors.text,Enum.Font.GothamMedium)
        self.countLabel=label(hero,"NODE 000000   /   0 SAMPLES",18,72,365,15,10,colors.muted,Enum.Font.Code)
        self.clock=label(hero,"00:00.000",398,24,215,38,31,colors.text,Enum.Font.Code)
        self.clock.TextXAlignment=Enum.TextXAlignment.Right
        label(hero,"RELATIVE SIMULATION TIME",396,71,217,15,9,colors.muted).TextXAlignment=Enum.TextXAlignment.Right
        label(self.window,"SESSION TIMELINE",24,195,250,16,10,colors.muted,Enum.Font.GothamMedium)
        self.duration=label(self.window,"00:00.000",450,195,206,16,11,colors.muted,Enum.Font.Code)
        self.duration.TextXAlignment=Enum.TextXAlignment.Right
        local track=frame(self.window,24,224,632,6,colors.raised); corner(track,3)
        self.fill=frame(track,0,0,0,6,colors.tomato); corner(self.fill,3)
        self.thumb=frame(track,-5,-3,12,12,colors.text); corner(self.thumb,6)
        self.scrub=make("TextButton",self.window,{Text="",Position=UDim2.fromOffset(24,211),
            Size=UDim2.fromOffset(632,30),BackgroundTransparency=1,AutoButtonColor=false})
        self.scope:Add(self.scrub.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                self:Scrub(input.Position.X)
            end
        end))
        self.tabs={}; self.pages={}; self.tabLines={}
        for i,name in ipairs({"Studio","Branches","Files"}) do
            self.tabs[name]=self:Button(self.window,name,24+(i-1)*132,254,124,32,function() self:Tab(name) end)
            self.tabLines[name]=frame(self.window,34+(i-1)*132,285,104,2,colors.tomato)
            local page=frame(self.window,24,300,632,254)
            page.BackgroundTransparency=1; page.Visible=false; self.pages[name]=page
        end
        self:Button(self.window,"New run",532,254,124,32,function() self:NewRun() end)
        self.actionButtons={}
        local function action(text,key,x,y,w,h,primary)
            local entry=self:Button(self.pages.Studio,text,x,y,w,h,function() self.app:Dispatch(key) end,primary)
            self.actionButtons[key]=entry
            self.scope:Add(entry.object.MouseEnter:Connect(function()
                if not entry.enabled then self.hint=if self.app.busy then "A map operation is running. Stop can cancel it." else self.app:ActionReason(key) end
            end))
            self.scope:Add(entry.object.MouseLeave:Connect(function() self.hint=nil end))
            return entry
        end
        action("●  Record","Record",0,0,208,48,true)
        action("▶  Play","Play",218,0,198,48)
        action("■  Stop","Stop",426,0,206,48)
        action("Prepare map","Prepare",0,62,148,38)
        action("Clone map","Clone",158,62,148,38)
        action("‹  Previous","PreviousFrame",316,62,98,38)
        action("Step +1","Step",424,62,110,38)
        action("Next  ›","NextFrame",544,62,88,38)
        self.markBox=self:Box(self.pages.Studio,"Character mark name","quick",0,114,230)
        self:Button(self.pages.Studio,"Save mark",240,114,184,38,function()
            local name=self.markBox.Text
            if #name==0 or #name>128 then self:Notice("Give the mark a name between 1 and 128 characters."); return end
            if not self.app.tree then self:Notice("Record a run before saving a character mark."); return end
            self:Run(function() self.app:Mark(name) end,true)
        end)
        self:Button(self.pages.Studio,"Restore mark",434,114,198,38,function()
            local name=self.markBox.Text
            if not self.app.tree or not self.app.tree.marks[name] then self:Notice("No character mark named "..name.."."); return end
            self:Run(function() self.app:Restore(name) end,true)
        end)
        local speeds={0.25,0.5,1,2,4}
        self.speedButton=self:Button(self.pages.Studio,"Speed  1×",0,166,180,38,function()
            self:Run(function()
                local i=table.find(speeds,self.app.speed) or 2
                self.app:SetSpeed(speeds[i%#speeds+1])
            end)
        end)
        self.modeButton=self:Button(self.pages.Studio,"Time-based replay",190,166,222,38,function()
            if self.app.mode=="playing" then self:Notice("Pause playback before changing replay mode."); return end
            self:Run(function() self.app.playbackMode=if self.app.playbackMode=="time" then "frames" else "time" end)
        end)
        self.cameraButton=self:Button(self.pages.Studio,"Camera  ON",422,166,210,38,function()
            self:Run(function() self.app:SetCamera(not self.app.camera) end)
        end)
        label(self.pages.Studio,"CHARACTER MARKS ONLY  ·  Full map rewind is not available yet.",0,220,632,24,11,colors.amber)
        self.branchCaption=label(self.pages.Branches,"Select a continuation to inspect its final recorded frame.",0,0,632,26,12,colors.muted)
        self.branchList=self:List(self.pages.Branches,0,38,632,204)
        self.fileBox=self:Box(self.pages.Files,"Run filename",config.File,0,0,380)
        self:Button(self.pages.Files,"Save",390,0,116,38,function() self:File("Save") end,true)
        self:Button(self.pages.Files,"Load",516,0,116,38,function() self:File("Load") end)
        self.fileList=self:List(self.pages.Files,0,52,632,140)
        self:Button(self.pages.Files,"Refresh files",0,204,184,38,function() self:Files() end)
        self:Button(self.pages.Files,"Load backup",194,204,214,38,function() self:File("Load","backup") end)
        self:Button(self.pages.Files,"Load pending",418,204,214,38,function() self:File("Load","pending") end)
        local footer=frame(self.window,24,564,632,36,colors.card); corner(footer,9)
        self.notice=label(footer,"Maps prepare automatically when you spawn. Prepare map retries setup.",12,4,608,28,11,colors.muted)
        self.notice.TextWrapped=true; self.notice.TextTruncate=Enum.TextTruncate.None
        self.launcher=self:Button(self.surface,"●  TomatoTAS  /  Open",16,16,210,40,function() self:Toggle(true) end,true)
        self.launcher.object.Visible=false
        self.scope:Add(self.header.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                self.drag={input=input,start=input.Position,x=self.x or 0,y=self.y or 0}
            end
        end))
        self.scope:Add(UIS.InputChanged:Connect(function(input)
            if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseMovement) then
                self.x=self.drag.x+input.Position.X-self.drag.start.X
                self.y=self.drag.y+input.Position.Y-self.drag.start.Y
                self:Fit()
            end
        end))
        self.scope:Add(UIS.InputEnded:Connect(function(input)
            if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then self.drag=nil end
        end))
        self.scope:Add(self.surface:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:Fit() end))
        self.screen.Parent=assert(Players.LocalPlayer:WaitForChild("PlayerGui",10),"PlayerGui unavailable")
        self:Fit(); self:Tab("Studio")
        local elapsed=0
        self.scope:Add(RS.Heartbeat:Connect(function(dt)
            elapsed+=dt
            if elapsed<0.1 or not self.window.Visible then return end
            elapsed=0
            local ok,err=pcall(function() self:Update() end)
            if not ok then
                warn("[TomatoTAS GUI] "..tostring(err))
                self:Destroy() -- leave the engine and hotkeys alive if presentation fails
            end
        end))
        self:Update()
    end
    function Panel:List(parent,x,y,w,h)
        local list=make("ScrollingFrame",parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
            BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),
            AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=colors.muted,
            ScrollingDirection=Enum.ScrollingDirection.Y})
        return list
    end
    function Panel:Rows(list,rows,callback,kind)
        if self.rowScopes[kind] then self.rowScopes[kind]:Destroy() end
        local scope=Scope.new(); self.rowScopes[kind]=scope
        for _,child in ipairs(list:GetChildren()) do child:Destroy() end
        list.CanvasPosition=Vector2.zero
        if #rows==0 then
            label(list,if kind=="branches" then "No branches yet. Record your first run in Studio." else "No saved runs. Enter a name above and save a recording.",12,14,590,40,12,colors.muted)
            return
        end
        for i,row in ipairs(rows) do
            local button=self:Button(list,row.text,0,(i-1)*37,620,31,function() callback(row.value) end,false,scope)
            button.object.TextXAlignment=Enum.TextXAlignment.Left
            make("UIPadding",button.object,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)})
        end
    end
    function Panel:Branches()
        local tree=self.app.tree
        local rows={}
        if tree then
            local tips=tree:Branches()
            self.branchCaption.Text=if #tips>60 then "Latest 60 continuations shown. Use the cycle hotkey to reach older branches."
                else "Select a continuation to inspect its final recorded frame."
            for i=#tips,math.max(1,#tips-59),-1 do
                local id=tips[i]
                table.insert(rows,{text=string.format("BRANCH %06d     /     %s",id,Model.clock(tree.nodes[id].frame.time)),value=id})
            end
        end
        self:Rows(self.branchList,rows,function(tip)
            if self.app.tree~=tree then self:Branches(); return end
            self:Run(function() self.app:SelectBranch(tip); self:Notice("Selected branch "..tip..".") end,true)
        end,"branches")
        self.branchTree=tree; self.branchCount=tree and #tree.nodes or 0
    end
    function Panel:Files()
        if self.app.busy then return end
        local ok,files=pcall(function() return self.app:ListFiles() end)
        if not ok then self:Notice("Could not list saved files: "..tostring(files),"error"); return end
        local rows={}
        for _,path in ipairs(files) do
            local name=Model.fileName(path)
            if name then table.insert(rows,{text=name.."   .fe2tomatas",value=name}) end
        end
        self:Rows(self.fileList,rows,function(name) self.fileBox.Text=name end,"files")
    end
    function Panel:File(method,source)
        if self.app.busy then self:Notice("Wait for the current map operation to finish."); return end
        local valid,reason=pcall(function() self.app:SetFile(self.fileBox.Text) end)
        if not valid then self:Notice(tostring(reason),"error"); return end
        self:Run(function()
            local ok=self.app:FileCommand(method,self.fileBox.Text,source)
            if ok then self.filesDirty=true end
        end)
    end
    function Panel:Tab(name)
        self.tab=name
        for key,page in pairs(self.pages) do
            page.Visible=key==name
            self.tabLines[key].Visible=key==name
            self.tabs[key].object.TextColor3=if key==name then colors.tomato else colors.muted
        end
        if name=="Files" then self:Files() elseif name=="Branches" then self:Branches() end
    end
    function Panel:Scrub(x)
        if self.app.busy then self:Notice("A map operation is running. Stop can cancel it."); return end
        if self.app.mode=="recording" or self.app.mode=="stepPending" or self.app.mode=="stepping" then
            self:Notice("Pause recording before seeking the timeline."); return
        end
        local tree=self.app.tree
        if not tree or #tree.nodes==0 then return end
        self:Run(function()
            local path=self.app.path or tree:Path()
            local ratio=(x-self.scrub.AbsolutePosition.X)/math.max(1,self.scrub.AbsoluteSize.X)
            local id=Model.frameAt(tree,path,ratio)
            if id then self.app:Seek(id) end
        end,true)
    end
    function Panel:Fit()
        if self.scope.dead then return end
        local size=self.surface.AbsoluteSize
        if size.X<=0 or size.Y<=0 then return end
        local scale=math.max(0.1,math.min(1,(size.X-24)/W,(size.Y-24)/H))
        self.scale.Scale=scale
        self.x=math.clamp(self.x or (size.X-W*scale)/2,8,math.max(8,size.X-W*scale-8))
        self.y=math.clamp(self.y or (size.Y-H*scale)/2,8,math.max(8,size.Y-H*scale-8))
        self.window.Position=UDim2.fromOffset(self.x,self.y)
    end
    function Panel:Toggle(visible)
        self.window.Visible=visible
        self.launcher.object.Visible=not visible
        if visible then self:Fit(); self:Update() end
    end
    function Panel:Update()
        if self.confirmTree~=self.app.tree or (self.confirmAt and os.clock()-self.confirmAt>4) then
            self.confirmTree=nil; self.confirmAt=nil
        end
        local state=Model.summary(self.app)
        self.mapLabel.Text=state.map
        self.clock.Text=Model.clock(state.time)
        self.duration.Text=Model.clock(state.duration)
        self.countLabel.Text=string.format("NODE %06d   /   %d SAMPLES",state.node,state.nodes)
        self.badge.Text=string.upper(state.mode)
        self.badge.TextColor3=if state.mode=="recording" then colors.tomato elseif state.mode=="preparing" then colors.amber else colors.green
        self.fill.Size=UDim2.new(state.progress,0,0,6)
        self.thumb.Position=UDim2.new(state.progress,-6,0,-3)
        self.actionButtons.Record.object.Text=if self.app.mode=="recording" then "Ⅱ  Pause recording" else "●  Record"
        self.actionButtons.Play.object.Text=if self.app.mode=="playing" then "Ⅱ  Pause playback" else "▶  Play"
        for action,entry in pairs(self.actionButtons) do
            self:Enabled(entry,action=="Stop" or (not self.app.busy and not self.app:ActionReason(action)))
        end
        self.speedButton.object.Text=string.format("Speed  %g×",self.app.speed)
        self.modeButton.object.Text=if self.app.playbackMode=="time" then "Time-based replay" else "Exact-frame replay"
        self.cameraButton.object.Text=if self.app.camera then "Camera  ON" else "Camera  OFF"
        local notice=self.app.lastNotice
        if self.hint then
            self.notice.Text=self.hint; self.notice.TextColor3=colors.muted
        elseif notice then
            self.notice.Text=(notice.text:match("^[^\n]+") or notice.text):sub(1,230)
            self.notice.TextColor3=if notice.level=="error" then colors.tomato elseif notice.level=="warning" then colors.amber else colors.muted
        end
        if self.tab=="Branches" and (self.branchTree~=self.app.tree or self.branchCount~=state.nodes)
            and os.clock()-(self.lastBranchRefresh or 0)>1 then
            self:Branches(); self.lastBranchRefresh=os.clock()
        end
        if self.tab=="Files" and self.filesDirty and not self.app.busy then self.filesDirty=false; self:Files() end
    end
    function Panel.new(app)
        local self=setmetatable({app=app,scope=Scope.new(),rowScopes={}},Panel)
        local ok,err=xpcall(function() self:Build() end,debug.traceback)
        if not ok then self:Destroy(); error(err,0) end
        return self
    end
    function Panel:Destroy()
        if self.scope.dead then return end
        for _,scope in pairs(self.rowScopes) do scope:Destroy() end
        self.scope:Destroy()
    end
    return Panel
end
