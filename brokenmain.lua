-- main.lua – Pixel Art Sprite Generator v2.0
-- Técnicas 8/16-bit, selective outline, paletas expandidas, animações clássicas

local gen, anim, ui, pal, exp, pre = {}, {}, {}, {}, {}, {}
local spr, hist, sets = nil, {}, {}
local COL = {
    bg = {.05,.05,.08},
    panel = {.1,.1,.12},
    pl = {.15,.15,.18},
    acc = {.3,.7,.9},
    accD = {.2,.5,.7},
    txt = {.9,.9,.9},
    dim = {.6,.6,.6},
    ok = {.3,.8,.3},
    warn = {.9,.7,.2},
    err = {.9,.3,.3},
    grid = {.2,.2,.25
}}

local DEF = {
    type="character", size=16, palette="NES",
    complex=50, sym="vertical", rough=30,
    colorCnt=6, seed=os.time(), anatomy=50,
    class="warrior", detail=50, outline=true,
    frameCnt=4, animSpd=0.1, style="organic",
    bodyRatio=4, lightDir="top-left", weaponTrail=false
}

------------------------------------------------
-- UTILS
------------------------------------------------
local U = {}
function U.clamp(v,min,max) return math.max(min,math.min(max,v)) end
function U.lerp(a,b,t) return a+(b-a)*t end
function U.noise(x,y,s)
    local f=function(t) return t*t*t*(t*(t*6-15)+10) end
    s=s or 0; x,y=x+s*.1,y+s*.1
    local X,Y=math.floor(x)%256,math.floor(y)%256
    local xf,yf=x-math.floor(x),y-math.floor(y)
    local u,v=f(xf),f(yf)
    local p={} for i=0,255 do p[i]=i end
    math.randomseed(s)
    for i=255,1,-1 do local j=math.random(0,i) p[i],p[j]=p[j],p[i] end
    local function g(h,x,y)
        h=h%4
        local u=h<2 and x or y
        local v=h<2 and y or x
        return ((h%2==0 and u or -u)+(h==1 or h==2 and -v or v))
    end
    local function P(v) return p[v%256] end
    local aa,ab,ba,bb=P(P(X)+Y),P(P(X)+Y+1),P(P(X+1)+Y),P(P(X+1)+Y+1)
    local x1=U.lerp(g(aa,xf,yf),g(ba,xf-1,yf),u)
    local x2=U.lerp(g(ab,xf,yf-1),g(bb,xf-1,yf-1),u)
    return U.lerp(x1,x2,v)
end
function U.copy(t)
    local r={}
    for k,v in pairs(t) do r[k]=(type(v)=='table' and U.copy(v) or v) end
    return r
end
function U.roundRect(x,y,w,h,r)
    love.graphics.rectangle("fill",x+r,y,w-r*2,h)
    love.graphics.rectangle("fill",x,y+r,w,h-r*2)
    love.graphics.circle("fill",x+r,y+r,r)
    love.graphics.circle("fill",x+w-r,y+r,r)
    love.graphics.circle("fill",x+r,y+h-r,r)
    love.graphics.circle("fill",x+w-r,y+h-r,r)
end
function U.dist(a,b) return math.sqrt(a*a+b*b) end

------------------------------------------------
-- PALETTE
------------------------------------------------
function pal:new()
    local o=setmetatable({},{__index=self})
    o.list={
        NES={
            {0,0,0},{.19,.19,.19},{.5,.5,.5},{1,1,1},
            {.74,.19,.19},{.94,.38,.38},{.19,.38,.74},{.38,.56,.94},
            {.19,.74,.19},{.38,.94,.38},{.74,.74,.19},{.94,.94,.38},
            {.74,.38,.19},{.94,.56,.38},{.74,.19,.74},{.94,.38,.94}
        },
        GameBoy={{.06,.22,.06},{.19,.38,.19},{.55,.67,.06},{.74,.89,.42}},
        C64={
            {0,0,0},{1,1,1},{.53,0,0},{.67,1,.93},
            {.8,.27,.8},{0,.8,.33},{0,0,.67},{1,1,.47},
            {.8,.47,0},{.47,.3,0},{1,.47,.47},{.33,.33,.33},
            {.47,.47,.47},{.67,1,.4},{0,.53,1},{.73,.73,.73}
        },
        SNES={
            {.1,.1,.1},{.3,.3,.3},{.6,.6,.6},{.9,.9,.9},
            {.8,.2,.2},{.9,.4,.4},{.2,.4,.8},{.4,.6,.9},
            {.2,.8,.2},{.4,.9,.4},{.8,.8,.2},{.9,.9,.4},
            {.8,.4,.2},{.9,.6,.4},{.8,.2,.8},{.9,.4,.9}
        }
    }
    o.cur="NES"
    return o
end
function pal:get() return self.list[self.cur] end
function pal:col(i,s)
    local t=self:get()
    return t[math.max(1,math.min(s.colorCnt,#t))]
end
function pal:rand(s) return self:col(math.random(1,s.colorCnt),s) end
function pal:shades(c,n)
    local t={}
    for i=1,n do
        t[i]={U.clamp(c[1]*(1-i*.15),0,1),
              U.clamp(c[2]*(1-i*.15),0,1),
              U.clamp(c[3]*(1-i*.15),0,1)}
    end
    return t
end

------------------------------------------------
-- GENERATOR
------------------------------------------------
function gen:new()
    return setmetatable({
        types={character=self.genChar,weapon=self.genWeap,item=self.genItem,tile=self.genTile}
    },{__index=self})
end
function gen:empty(sz)
    local s={}
    for y=1,sz do s[y]={} for x=1,sz do s[y][x]={0,0,0,0} end end
    return s
end
function gen:sym(spr,sym)
    local sz=#spr
    if sym=="vertical" or sym=="both" then
        for y=1,sz do for x=1,math.floor(sz/2) do spr[y][sz-x+1]=U.copy(spr[y][x]) end end
    end
    if sym=="horizontal" or sym=="both" then
        for y=1,math.floor(sz/2) do for x=1,sz do spr[sz-y+1][x]=U.copy(spr[y][x]) end end
    end
    return spr
end
function gen:selOutline(spr,dir)
    local sz=#spr
    local dirs={["top-left"]={-1,-1},["top-right"]={1,-1},front={0,-1}}
    local dx,dy=(dirs[dir] or dirs["top-left"])[1],(dirs[dir] or dirs["top-left"])[2]
    local out=self:empty(sz)
    for y=1,sz do for x=1,sz do out[y][x]=U.copy(spr[y][x]) end end
    for y=2,sz-1 do for x=2,sz-1 do
        if spr[y][x][4]>0 then
            for oy=-1,1 do for ox=-1,1 do
                if spr[y+oy][x+ox][4]==0 then
                    local shade=spr[y][x]
                    out[y+oy][x+ox]={shade[1]*.3,shade[2]*.3,shade[3]*.3,1}
                end
            end end
        end
    end end
    return out
end
function gen:genChar(s)
    math.randomseed(s.seed)
    local sz=s.size
    local spr=self:empty(sz)
    local struct={warrior={h=.3,b=.4},mage={h=.35,b=.3},archer={h=.28,b=.35}}
    local st=struct[s.class] or struct.warrior
    local scale=s.anatomy/50
    local bodyH=math.floor(sz/st.bodyRatio)

    -- head
    local headY=1
    local headS=math.floor(sz*st.h*scale)
    local cx=sz/2
    for y=headY,headY+headS do
        for x=cx-headS/2,cx+headS/2 do
            if U.dist(x-cx,y-headY-headS/2)<headS/2 and U.noise(x*.3,y*.3,s.seed)>-.3 then
                local c=pal:rand(s)
                spr[y][x]={c[1],c[2],c[3],1}
            end
        end
    end

    -- body
    local bodyY=headY+headS
    local bodyH2=math.floor(sz*st.b*scale)
    for y=bodyY,bodyY+bodyH2 do
        local w=sz*st.b*scale*(1-(y-bodyY)/bodyH2*.2)
        for x=cx-w/2,cx+w/2 do
            if U.noise(x*.2,y*.2,s.seed+100)>-.4 then
                local c=pal:rand(s)
                spr[y][x]={c[1],c[2],c[3],1}
            end
        end
    end

    -- limbs
    local armY=bodyY+bodyH2*.2
    local armL=math.floor(sz*.3*scale)
    for i=0,armL do
        local x=cx-(sz*.25*scale)-i*.5
        local y=armY+i
        if x>0 and y<=sz then
            local c=pal:rand(s)
            spr[math.floor(y)][math.floor(x)]={c[1],c[2],c[3],1}
        end
    end
    for i=0,sz-(armY+armL) do
        local x=cx-(sz*.15*scale)
        local y=armY+armL+i
        if x>0 and y<=sz then
            local c=pal:rand(s)
            spr[math.floor(y)][math.floor(x)]={c[1],c[2],c[3],1}
        end
    end

    spr=self:sym(spr,s.sym)
    if s.outline then spr=self:selOutline(spr,s.lightDir) end
    return spr
end
function gen:genWeap(s)
    math.randomseed(s.seed)
    local sz=s.size
    local spr=self:empty(sz)
    local t=s.seed%3
    if t==0 then -- sword
        for y=1,sz*.7 do
            local w=sz*.15*(1-y/(sz*.7)*.5)
            for x=sz/2-w/2,sz/2+w/2 do
                spr[y][x]={.8,.8,.9,1}
            end
        end
        for y=sz*.7,sz do
            for x=sz/2-1,sz/2+1 do
                spr[y][x]={.4,.2,.1,1}
            end
        end
    elseif t==1 then -- axe
        for y=1,sz do spr[y][sz/2]={.4,.2,.1,1} end
        for y=1,sz*.4 do
            for x=sz/2,sz/2+sz*.3 do
                if math.abs(y-sz*.2)<sz*.2-(x-sz/2) then
                    spr[y][x]={.7,.7,.8,1}
                end
            end
        end
    else -- staff
        for y=sz*.2,sz do spr[y][sz/2]={.5,.3,.2,1} end
        for y=1,sz*.2 do
            for x=sz/2-sz*.1,sz/2+sz*.1 do
                if U.dist(x-sz/2,y-sz*.1)<sz*.1 then
                    local c=pal:rand(s)
                    spr[y][x]={c[1],c[2],c[3],1}
                end
            end
        end
    end
    spr=self:sym(spr,s.sym)
    if s.outline then spr=self:selOutline(spr,s.lightDir) end
    return spr
end
function gen:genItem(s)
    math.randomseed(s.seed)
    local sz=s.size
    local spr=self:empty(sz)
    local t=s.seed%3
    if t==0 then -- potion
        for y=sz*.3,sz do
            local w=sz*.4*(1-math.abs(y-sz*.65)/(sz*.35)*.3)
            for x=sz/2-w/2,sz/2+w/2 do
                local c=pal:rand(s)
                spr[y][x]={c[1]*.8,c[2]*.8,c[3],.9}
            end
        end
        for y=sz*.2,sz*.3 do
            for x=sz/2-2,sz/2+2 do
                spr[y][x]={.6,.4,.3,1}
            end
        end
    elseif t==1 then -- gem
        local cx,cy=sz/2,sz/2
        for y=cy-sz*.3,cy+sz*.3 do
            for x=cx-sz*.3,cx+sz*.3 do
                if U.dist(x-cx,y-cy)<sz*.3 then
                    local c=pal:rand(s)
                    spr[y][x]={c[1],c[2],c[3],1}
                end
            end
        end
    else -- chest
        for y=sz*.5,sz do
            for x=sz*.15,sz*.85 do
                spr[y][x]={.5,.3,.1,1}
            end
        end
        for y=sz*.45,sz*.5 do
            for x=sz*.15,sz*.85 do
                spr[y][x]={.6,.4,.2,1}
            end
        end
    end
    if s.outline then spr=self:selOutline(spr,s.lightDir) end
    return spr
end
function gen:genTile(s)
    math.randomseed(s.seed)
    local sz=s.size
    local spr=self:empty(sz)
    local base=pal:rand(s)
    for y=1,sz do for x=1,sz do spr[y][x]={base[1],base[2],base[3],1} end end
    local ns=.1+s.complex/250
    for y=1,sz do for x=1,sz do
        local n=U.noise(x*ns,y*ns,s.seed)
        if n>.3 then
            local c2=pal:rand(s)
            spr[y][x]={U.lerp(base[1],c2[1],.3),U.lerp(base[2],c2[2],.3),U.lerp(base[3],c2[3],.3),1}
        elseif n<-.3 then
            spr[y][x]={base[1]*.8,base[2]*.8,base[3]*.8,1}
        end
    end end
    return spr
end
function gen:gen(s)
    pal.cur=s.palette
    return (self.types[s.type] or self.types.character)(self,s)
end

------------------------------------------------
-- ANIMATION
------------------------------------------------
function anim:new()
    return setmetatable({anims={},cur="idle",frame=1,tmr=0,play=true},{__index=self})
end
function anim:empty(sz)
    local s={}
    for y=1,sz do s[y]={} for x=1,sz do s[y][x]={0,0,0,0} end end
    return s
end
function anim:create(name,base,fc,s)
    local f={}
    for i=1,fc do
        local fr=U.copy(base)
        if name=="idle" then
            local o=math.sin((i-1)/(fc-1)*math.pi*2)*1
            local n=self:empty(#base)
            for y=1,#base do
                for x=1,#base do
                    local ny=y+math.floor(o*(y/#base))
                    if ny>=1 and ny<=#base then n[ny][x]=base[y][x] end
                end
            end
            f[i]=n
        elseif name=="walk" then
            local o=math.sin((i-1)/(fc-1)*math.pi*2)*2
            local n=self:empty(#base)
            for y=1,#base do
                for x=1,#base do
                    local nx=x+math.floor(o)
                    if nx>=1 and nx<=#base then n[y][nx]=base[y][x] end
                end
            end
            f[i]=n
        elseif name=="attack" then
            local ang=math.sin((i-1)/(fc-1)*math.pi)*.3
            local n=self:empty(#base)
            local cx,cy=#base/2,#base/2
            for y=1,#base do
                for x=1,#base do
                    local dx,dy=x-cx,y-cy
                    local nx=math.floor(cx+dx*math.cos(ang)-dy*math.sin(ang))
                    local ny=math.floor(cy+dx*math.sin(ang)+dy*math.cos(ang))
                    if nx>=1 and nx<=#base and ny>=1 and ny<=#base then
                        n[ny][nx]=base[y][x]
                    end
                end
            end
            f[i]=n
        elseif name=="hurt" then
            local flash=math.sin((i-1)/(fc-1)*math.pi*4)*.5+.5
            local n=U.copy(base)
            for y=1,#base do
                for x=1,#base do
                    if n[y][x][4]>0 then
                        n[y][x][1]=math.min(1,n[y][x][1]+flash*.5)
                        n[y][x][2]=n[y][x][2]*(1-flash*.5)
                        n[y][x][3]=n[y][x][3]*(1-flash*.5)
                    end
                end
            end
            f[i]=n
        elseif name=="death" then
            local t=(i-1)/(fc-1)
            local n=self:empty(#base)
            for y=1,#base do
                for x=1,#base do
                    local ny=y+math.floor(t*#base*.5)
                    if ny>=1 and ny<=#base and base[y][x][4]>0 then
                        n[ny][x]={base[y][x][1],base[y][x][2],base[y][x][3],base[y][x][4]*(1-t)}
                    end
                end
            end
            f[i]=n
        else f[i]=fr end
    end
    self.anims[name]={frames=f,fc=fc,spd=s.animSpd}
end
function anim:upd(dt)
    if not self.play then return end
    self.tmr=self.tmr+dt
    local a=self.anims[self.cur]
    if a and self.tmr>=a.spd then
        self.tmr=0
        self.frame=self.frame+1
        if self.frame>a.fc then self.frame=1 end
    end
end
function anim:get() local a=self.anims[self.cur] return a and a.frames[self.frame] end
function anim:set(n) if self.anims[n] then self.cur=n;self.frame=1;self.tmr=0 end end
function anim:toggle() self.play=not self.play end

------------------------------------------------
-- UI
------------------------------------------------
function ui:new()
    local o=setmetatable({},{__index=self})
    o.W,o.H=love.graphics.getDimensions()
    o.panels={
        left={x=0,y=0,w=280,h=o.H},
        center={x=280,y=0,w=o.W-560,h=o.H-120},
        right={x=o.W-280,y=0,w=280,h=o.H},
        bottom={x=280,y=o.H-120,w=o.W-560,h=120}
    }
    o.fonts={
        small=love.graphics.newFont(11),
        reg=love.graphics.newFont(13),
        med=love.graphics.newFont(16),
        big=love.graphics.newFont(20),
        title=love.graphics.newFont(24)
    }
    o:initControls()
    return o
end
function ui:initControls()
    local y=50
    local pad=20
    local w=240
    self.ctrls={
        type={"dropdown","Type",{"character","weapon","item","tile"},1},
        size={"slider","Size",8,32,16},
        pal={"dropdown","Palette",{"NES","GameBoy","C64","SNES"},1},
        complex={"slider","Complexity",0,100,50},
        sym={"dropdown","Symmetry",{"none","vertical","horizontal","both"},2},
        rough={"slider","Roughness",0,100,30},
        colCnt={"slider","Colors",2,16,6},
        seed={"input","Seed",tostring(os.time())},
        anatomy={"slider","Anatomy",20,100,50},
        class={"dropdown","Class",{"warrior","mage","archer"},1},
        detail={"slider","Detail",0,100,50},
        outline={"check","Outline",true},
        frameCnt={"slider","Frames",2,8,4},
        spd={"slider","Anim Spd",0.05,0.5,0.1},
        style={"dropdown","Style",{"organic","blocky","geometric"},1},
        bodyRatio={"slider","Head:Body",2,8,4},
        lightDir={"dropdown","Light Dir",{"top-left","top-right","front"},1},
        trail={"check","Weapon Trail",false}
    }
    self.order={"type","size","pal","complex","sym","rough","colCnt","seed","anatomy","class","detail","outline","frameCnt","spd","style","bodyRatio","lightDir","trail"}
    for _,k in ipairs(self.order) do
        local v=self.ctrls[k]
        v.x,v.y=pad,y
        if v[1]=="slider" then v.w=w;v.min,v.max,v.val=v[3],v[4],v[5];v.pct=(v.val-v.min)/(v.max-v.min) end
        y=y+40
    end
    self.btns={
        gen={x=pad,y=self.panels.left.h-220,w=115,h=35,txt="Generate [SPACE]",col=COL.acc},
        rnd={x=pad+130,y=self.panels.left.h-220,w=115,h=35,txt="Randomize [R]",col=COL.warn},
        save={x=pad,y=self.panels.left.h-175,w=115,h=35,txt="Save [S]",col=COL.ok},
        sheet={x=pad+130,y=self.panels.left.h-175,w=115,h=35,txt="Sheet [A]",col=COL.ok},
        batch={x=pad,y=self.panels.left.h-130,w=240,h=35,txt="Batch [ENTER]",col=COL.accD}
    }
end
function ui:updSets()
    for k,v in pairs(self.ctrls) do
        if v[1]=="dropdown" then sets[k]=v[2][v[3]] elseif v[1]=="slider" then sets[k]=v.val elseif v[1]=="check" then sets[k]=v[4] elseif v[1]=="input" then sets[k]=tonumber(v[4]) or os.time() end
    end
    pal.cur=sets.palette
end
function ui:draw()
    love.graphics.clear(COL.bg)
    -- panels
    love.graphics.setColor(COL.panel)
    love.graphics.rectangle("fill",self.panels.left.x,self.panels.left.y,self.panels.left.w,self.panels.left.h)
    love.graphics.rectangle("fill",self.panels.right.x,self.panels.right.y,self.panels.right.w,self.panels.right.h)
    love.graphics.rectangle("fill",self.panels.bottom.x,self.panels.bottom.y,self.panels.bottom.w,self.panels.bottom.h)
    love.graphics.setColor(COL.pl)
    love.graphics.rectangle("fill",self.panels.center.x,self.panels.center.y,self.panels.center.w,self.panels.center.h)
    -- title
    love.graphics.setFont(self.fonts.title)
    love.graphics.setColor(COL.acc)
    love.graphics.print("PIXEL ART GENERATOR v2",20,15)
    -- controls
    love.graphics.setFont(self.fonts.reg)
    local mx,my=love.mouse.getPosition()
    for _,k in ipairs(self.order) do
        local v=self.ctrls[k]
        if v[1]=="slider" then
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[2],v.x,v.y)
            U.roundRect(v.x,v.y+18,v.w,6,3)
            love.graphics.setColor(COL.accD)
            U.roundRect(v.x,v.y+18,v.w*v.pct,6,3)
            love.graphics.setColor(COL.acc)
            love.graphics.circle("fill",v.x+v.w*v.pct,v.y+21,8)
            love.graphics.setColor(COL.dim)
            love.graphics.print(math.floor(v.val),v.x+v.w-self.fonts.reg:getWidth(math.floor(v.val)),v.y)
        elseif v[1]=="dropdown" then
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[2],v.x,v.y)
            U.roundRect(v.x,v.y+18,v.w,24,4)
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[2][v[3]],v.x+8,v.y+22)
            love.graphics.print("▼",v.x+v.w-20,v.y+22)
        elseif v[1]=="check" then
            U.roundRect(v.x,v.y,20,20,4)
            if v[4] then
                love.graphics.setColor(COL.acc)
                love.graphics.setLineWidth(3)
                love.graphics.line(v.x+5,v.y+10,v.x+8,v.y+14,v.x+15,v.y+6)
                love.graphics.setLineWidth(1)
            end
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[2],v.x+28,v.y+2)
        elseif v[1]=="input" then
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[2],v.x,v.y)
            U.roundRect(v.x,v.y+18,v.w,24,4)
            love.graphics.setColor(COL.txt)
            love.graphics.print(v[4],v.x+8,v.y+22)
        end
    end
    -- buttons
    for _,b in pairs(self.btns) do
        local hover=mx>=b.x and mx<=b.x+b.w and my>=b.y and my<=b.y+b.h
        love.graphics.setColor(hover and {b.col[1]*1.2,b.col[2]*1.2,b.col[3]*1.2} or b.col)
        U.roundRect(b.x,b.y,b.w,b.h,6)
        love.graphics.setColor(0.1,0.1,0.1)
        love.graphics.setFont(self.fonts.med)
        local tw=self.fonts.med:getWidth(b.txt)
        love.graphics.print(b.txt,b.x+(b.w-tw)/2,b.y+8)
    end
    -- preview
    if spr then
        local frame=anim:get() or spr
        local sz=#frame
        local scl=math.min(math.min(self.panels.center.w*.8,self.panels.center.h*.8)/sz,16)
        local px=self.panels.center.x+(self.panels.center.w-sz*scl)/2
        local py=self.panels.center.y+(self.panels.center.h-sz*scl)/2
        love.graphics.setColor(COL.bg)
        U.roundRect(px-10,py-10,sz*scl+20,sz*scl+20,8)
        -- grid
        love.graphics.setColor(COL.grid)
        for i=0,sz do
            love.graphics.line(px,py+i*scl,px+sz*scl,py+i*scl)
            love.graphics.line(px+i*scl,py,px+i*scl,py+sz*scl)
        end
        -- sprite
        for y=1,sz do for x=1,sz do
            local p=frame[y][x]
            if p[4]>0 then
                love.graphics.setColor(p)
                love.graphics.rectangle("fill",px+(x-1)*scl,py+(y-1)*scl,scl,scl)
            end
        end end
    else
        love.graphics.setColor(COL.dim)
        love.graphics.setFont(self.fonts.big)
        love.graphics.print("Press SPACE to generate",self.panels.center.x+100,self.panels.center.y+self.panels.center.h/2-10)
    end
    -- history
    love.graphics.setFont(self.fonts.med)
    love.graphics.setColor(COL.txt)
    love.graphics.print("HISTORY",self.panels.right.x+20,20)
    local y=55
    local ts=72
    local gap=10
    for i,histSpr in ipairs(hist) do
        local col=(i-1)%3
        local x=self.panels.right.x+20+col*(ts+gap)
        local hy=y+math.floor((i-1)/3)*(ts+gap)
        love.graphics.setColor(COL.pl)
        U.roundRect(x-2,hy-2,ts+4,ts+4,4)
        local hs=ts/#histSpr
        for py=1,#histSpr do for px=1,#histSpr do
            local p=histSpr[py][px]
            if p[4]>0 then
                love.graphics.setColor(p)
                love.graphics.rectangle("fill",x+(px-1)*hs,hy+(py-1)*hs,hs,hs)
            end
        end end
        love.graphics.setColor(COL.dim)
        love.graphics.print("#"..i,x+2,hy+ts-12)
    end
    -- timeline
    love.graphics.setFont(self.fonts.med)
    love.graphics.setColor(COL.txt)
    love.graphics.print("ANIMATION",self.panels.bottom.x+20,10)
    local anims={"idle","walk","attack","hurt","death"}
    local bw=80
    for i,a in ipairs(anims) do
        local bx=self.panels.bottom.x+20+(i-1)*(bw+5)
        local by=35
        love.graphics.setColor(anim.cur==a and COL.acc or COL.pl)
        U.roundRect(bx,by,bw,25,4)
        love.graphics.setColor(anim.cur==a and {0.1,0.1,0.1} or COL.txt)
        love.graphics.setFont(self.fonts.small)
        love.graphics.print(a:upper(),bx+(bw-self.fonts.small:getWidth(a:upper()))/2,by+6)
    end
    -- timeline track
    local tx,ty,tw,th=self.panels.bottom.x+20,70,self.panels.bottom.w-120,30
    love.graphics.setColor(COL.pl)
    U.roundRect(tx,ty,tw,th,4)
    local a=anim.anims[anim.cur]
    if a then
        local fw=tw/a.fc
        for i=1,a.fc do
            love.graphics.setColor(i==anim.frame and COL.acc or COL.grid)
            U.roundRect(tx+(i-1)*fw+2,ty+2,fw-4,th-4,2)
            love.graphics.setColor(i==anim.frame and {0.1,0.1,0.1} or COL.txt)
            love.graphics.print(i,tx+(i-1)*fw+fw/2-self.fonts.reg:getWidth(i)/2,ty+8)
        end
    end
    -- play
    love.graphics.setColor(anim.play and COL.warn or COL.ok)
    U.roundRect(tx+tw+10,ty,70,th,4)
    love.graphics.setColor(0.1,0.1,0.1)
    love.graphics.print(anim.play and "PAUSE" or "PLAY",tx+tw+10+(70-self.fonts.reg:getWidth(anim.play and "PAUSE" or "PLAY"))/2,ty+8)
end
function ui:gen()
    self:updSets()
    spr=gen:gen(sets)
    table.insert(hist,1,U.copy(spr))
    if #hist>24 then table.remove(hist) end
    for _,a in ipairs({"idle","walk","attack","hurt","death"}) do
        anim:create(a,spr,sets.frameCnt,sets)
    end
end
function ui:rand()
    for _,k in ipairs(self.order) do
        local v=self.ctrls[k]
        if v[1]=="slider" then
            v.val=math.random(v.min,v.max)
            v.pct=(v.val-v.min)/(v.max-v.min)
        elseif v[1]=="dropdown" then
            v[3]=math.random(1,#v[2])
        elseif v[1]=="check" then
            v[4]=math.random()>.5
        elseif v[1]=="input" then
            v[4]=tostring(os.time()+math.random(1000))
        end
    end
end
function ui:save()
    if spr then exp:save(spr,"sprite_"..os.time()..".png") end
end
function ui:sheet()
    if anim.anims[anim.cur] then exp:sheet(anim.anims[anim.cur],"sheet_"..os.time()..".png") end
end

------------------------------------------------
-- EXPORT
------------------------------------------------
function exp:new() return setmetatable({},{__index=self}) end
function exp:save(spr,name)
    local sz=#spr
    local id=love.image.newImageData(sz,sz)
    for y=1,sz do for x=1,sz do
        local p=spr[y][x]
        id:setPixel(x-1,y-1,p[1],p[2],p[3],p[4])
    end end
    id:encode("png",name)
    print("saved "..name)
end
function exp:sheet(a,name)
    local sz=#a.frames[1]
    local id=love.image.newImageData(sz*a.fc,sz)
    for i=1,a.fc do
        local off=(i-1)*sz
        for y=1,sz do for x=1,sz do
            local p=a.frames[i][y][x]
            id:setPixel(off+x-1,y-1,p[1],p[2],p[3],p[4])
        end end
    end
    id:encode("png",name)
    print("saved "..name)
end

------------------------------------------------
-- LOVE
------------------------------------------------
function love.load()
    love.window.setTitle("Pixel Art Generator v2")
    love.window.setMode(1280,800,{resizable=false})
    gen,anim,ui,pal,exp=gen:new(),anim:new(),ui:new(),pal:new(),exp:new()
    for k,v in pairs(DEF) do sets[k]=v end
    ui:gen()
end
function love.update(dt) anim:upd(dt) end
function love.draw() ui:draw() end
function love.mousepressed(x,y,b)
    if b==1 then
        -- sliders
        for _,k in ipairs(ui.order) do
            local v=ui.ctrls[k]
            if v[1]=="slider" and x>=v.x and x<=v.x+v.w and y>=v.y+10 and y<=v.y+30 then
                v.active=true
            end
        end
        -- buttons
        for _,b in pairs(ui.btns) do
            if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
                if _=="gen" then ui:gen()
                elseif _=="rnd" then ui:rand(); ui:gen()
                elseif _=="save" then ui:save()
                elseif _=="sheet" then ui:sheet()
                elseif _=="batch" then for i=1,10 do ui:rand(); ui:gen() end end
            end
        end
        -- dropdown
        for _,k in ipairs(ui.order) do
            local v=ui.ctrls[k]
            if v[1]=="dropdown" and x>=v.x and x<=v.x+240 and y>=v.y+18 and y<=v.y+42 then
                v[3]=v[3]%#v[2]+1
            end
        end
        -- check
        for _,k in ipairs(ui.order) do
            local v=ui.ctrls[k]
            if v[1]=="check" and x>=v.x and x<=v.x+20 and y>=v.y and y<=v.y+20 then
                v[4]=not v[4]
            end
        end
        -- timeline
        local anims={"idle","walk","attack","hurt","death"}
        for i,a in ipairs(anims) do
            local bx=ui.panels.bottom.x+20+(i-1)*(80+5)
            if x>=bx and x<=bx+80 and y>=35 and y<=60 then anim:set(a) end
        end
        -- play
        local tx,tw=ui.panels.bottom.x+20,ui.panels.bottom.w-120
        if x>=tx+tw+10 and x<=tx+tw+80 and y>=70 and y<=100 then anim:toggle() end
        -- history
        local ts=72
        for i,histSpr in ipairs(hist) do
            local col=(i-1)%3
            local hx=ui.panels.right.x+20+col*(ts+10)
            local hy=55+math.floor((i-1)/3)*(ts+10)
            if x>=hx and x<=hx+ts and y>=hy and y<=hy+ts then
                spr=histSpr
                for _,a in ipairs({"idle","walk","attack","hurt","death"}) do
                    anim:create(a,spr,sets.frameCnt,sets)
                end
            end
        end
    end
end
function love.mousereleased(x,y,b)
    for _,k in ipairs(ui.order) do
        local v=ui.ctrls[k]
        if v[1]=="slider" then v.active=false end
    end
end
function love.mousemoved(x,y)
    for _,k in ipairs(ui.order) do
        local v=ui.ctrls[k]
        if v[1]=="slider" and v.active then
            v.pct=U.clamp((x-v.x)/v.w,0,1)
            v.val=v.min+(v.max-v.min)*v.pct
        end
    end
end
function love.keypressed(k)
    if k=="space" then ui:gen()
    elseif k=="r" then ui:rand(); ui:gen()
    elseif k=="s" then ui:save()
    elseif k=="a" then ui:sheet()
    elseif k=="return" then for i=1,10 do ui:rand(); ui:gen() end end
end