-- 写入文件
local function writefile(filename, info)
    local wfile=io.open(filename, "w") --写入文件(w覆盖)
    assert(wfile)  --打开时验证是否出错      
    wfile:write(info)  --写入传入的内容
    wfile:close()  --调用结束后记得关闭
end

-- 检测路径是否目录
local function is_dir(sPath)
    if type(sPath) ~= "string" then return false end

    local response = os.execute( "cd " .. sPath )
    if response == 0 then
        return true
    end
    return false
end

-- 检测文件是否存在
local file_exists = function(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

-- 逻辑区

local param = {}
local cjson = require("cjson")
local area = nil
local originalUri = ngx.var.uri;
local originalFile = ngx.var.file;
-- /group1/M00/01/04/OkTuVFRQvaWADb-0AADjPzRCCNY327.html_100x100_m1.html
local index = string.find(ngx.var.uri, "([0-9]+)x([0-9]+)");  
if index then 
    originalUri = string.sub(ngx.var.uri, 0, index-2);  
    -- /group1/M00/01/04/OkTuVFRQvaWADb-0AADjPzRCCNY327.html
    area = string.sub(ngx.var.uri, index);  
    -- 100x100_m1.html
    index = string.find(area, "([.])");  
    area = string.sub(area, 0, index-1);  
    -- 100x100_m1
    --/M00/01/04/OkTuVFRQvaWADb-0AADjPzRCCNY327.html_100x100_m1.html
    local index = string.find(originalFile, "([0-9]+)x([0-9]+)");  
    originalFile = string.sub(originalFile, 0, index-2)
    --/M00/01/04/OkTuVFRQvaWADb-0AADjPzRCCNY327.html
end

--如果不是要求裁剪，那就直接返回从云上下载的数据
if area == nil then
    local fileid = string.sub(originalUri, 2);
    -- main
    local fastdfs = require('restyfastdfs')
    local fdfs = fastdfs:new()
    fdfs:set_tracker("42.62.32.177", 22122)
    fdfs:set_timeout(10000)
    fdfs:set_tracker_keepalive(0, 100)
    fdfs:set_storage_keepalive(0, 100)
    local data = fdfs:do_download(fileid)
    if not data then
        ngx.say("ERR")
    else
        ngx.print(data)
    end
    return
end

--验证是合法的裁剪模式 数字x数字_m[0-3]

local first,last = string.find(area, "([0-9]+)x([0-9]+)_m([0-3])");  
if(first~=1 or last~=string.len(area)) then
    ngx.header.debug = "bad param, no such model"
    ngx.exit(400)
end

--验证合法，先看文件是否存在已经处理好的文件,有的话直接返回
if file_exists(ngx.var.file) then
    --ngx.req.set_uri(ngx.var.uri, true);  
    ngx.exec(ngx.var.uri)
    return
end
ngx.header.debug = "no processed file"

if not file_exists(originalFile) then
    local fileid = string.sub(originalUri, 2);
    ngx.header.down = fileid
    -- main
    local fastdfs = require('restyfastdfs')
    local fdfs = fastdfs:new()
    fdfs:set_tracker("42.62.32.177", 22122)
    fdfs:set_timeout(10000)
    fdfs:set_tracker_keepalive(0, 100)
    fdfs:set_storage_keepalive(0, 100)
    local data = fdfs:do_download(fileid)
    if data then
       -- check image dir
        if not is_dir(ngx.var.image_dir) then
            os.execute("mkdir -p " .. ngx.var.image_dir)
        end
        writefile(originalFile, data)
    end
end


local index = string.find(area, "_");  
local size = string.sub(area, 0, index-1)
local model = string.sub(area, index+1)
local index = string.find(size, "x");  
local width = string.sub(size, 0, index-1)
local height = string.sub(size, index+1)

-- m1 定宽等比绽放，小于宽度不处理
-- gm convert t.jpg -resize "300x100000>" -quality 30 output_1.jpg

-- m2 等比绽放，裁剪，比较适合头象，logo之类的需要固定大小的展示
-- gm convert sh.jpg -thumbnail "100x100^" -gravity center -extent 100x100 -quality 30 output_3.jpg

-- m3 等比绽放，不足会产生白边
-- gm convert sh.jpg -thumbnail "100x100" -gravity center -extent 100x100 -quality 30 output_3.jpg

local command = "";
if (model == "m1") then
    command = "gm convert " .. originalFile  
    .. " -resize \"" .. width .."x100000>\"" 
    .. " -background \"#fafafa\" "
    .. " -quality 90 "
    .. ngx.var.file; 
elseif (model == "m2") then
    command = "gm convert " .. originalFile  
    .. " -thumbnail \"" .. size .."^\" " 
    .. " -gravity center "
    .. " -background \"#fafafa\" "
    .. " -extent " .. size
    .. " -quality 90 "
    .. ngx.var.file; 
elseif (model == "m3") then
    command = "gm convert " .. originalFile  
    .. " -thumbnail " .. size .." " 
    .. " -gravity center "
    .. " -background \"#fafafa\" "
    .. " -extent " .. size
    .. " -quality 90 "
    .. ngx.var.file; 
end
ngx.header.command = command;
os.execute(command);  

if file_exists(ngx.var.file) then
    --ngx.req.set_uri(ngx.var.uri, true);  
    ngx.exec(ngx.var.uri)
else
    ngx.exit(404)
end