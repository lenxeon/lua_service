local function writefile(filename, data)
    local wfile=io.open(filename, "w") --写入文件(w覆盖)
    assert(wfile)  --打开时验证是否出错
    wfile:write(data)  --写入传入的内容
    wfile:close()  --调用结束后记得关闭
end

--获取文件大小
local function length_of_file(filename)
    local fh = assert(io.open(filename, "rb"))
    local len = assert(fh:seek("end"))
    fh:close()
    return len
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

-- 根据文件是否存，获得文件的Content-Length信息
function length_c()
    if is_dir(dir) then
        local c_file = dir.."/content_length";
        os.execute("stat "..min_file_path.." -c %s > "..c_file);
        io.input(c_file);
        C_length=io.read("*line");
        --print(C_length);
        ngx.header["Content-Length"] = C_length;
    end
end


-- http://localhost/img_crop_service/m1/100/120/80/123.jpg?url=http图像地址

-- 第一步：准备参数阶段
local model = ngx.var.model;
local width = ngx.var.width;
local height = ngx.var.height;
local quality = ngx.var.quality;
local img_root = ngx.var.img_root;
local url = ngx.var.url;
if (model == "m9") then
    width = 0;
    height = 0;
    quality = 0;
end

--根据url推算文件应该存放在哪个位置,存放规则:md5(url)前三位/md5(url)次三位/md5
local md5 = ngx.md5(url);
local first = string.sub(md5, 0, 3);
local second = string.sub(md5, 4, 6);
--图片的存放目录
local dir = img_root.."/"..first.."/"..second.."/";
--图片原图位置
local ori_file_path = dir..md5;
--图片缩略图名称及位置
local min_file_name = md5.."_"..width.."x"..height.."_"..model.."_"..quality;
local min_file_path = dir..min_file_name;

length_c();

------ngx.header["mmm"] = model;

ngx.header["step"] = 1;

--第二步：是否已经生成过了，如果生成过了利用location.capture特性跳转到conf中配置的另一个路径上直接访问
if file_exists(min_file_path) then
    ngx.header["step"] = 2;
    ------ngx.header["min_file_path"] = min_file_path;
    -- /imgservice/603/9eb/6039ebd7e2f78f755cccf47907174c00_100x100_m1
    local redirect = "/img_service/"..first.."/"..second.."/"..min_file_name;
    ngx.header["redirect"] = redirect;
    local res = ngx.location.capture(redirect)
    if res.status == 200 then
      ngx.print(res.body)
    end
    ngx.exit(200)
end


--第三步：原图在不在，不在下载
if not file_exists(ori_file_path) then
    ngx.header["step"] = 3.0;
    ------ngx.header["ori_file_path"] = ori_file_path;
    local http = require("resty.http")
    --创建http客户端实例
    local httpc = http.new()
    url = (string.gsub(url, "www.6study.com", "127.0.0.1"))
    url = (string.gsub(url, "6study.com", "127.0.0.1"))
    url = (string.gsub(url, "localhost", "127.0.0.1"))

    ngx.header["url"] = "["..url.."]";
    -- ngx.exit(200)

    local resp, err = httpc:request_uri(url, {
        method = "GET",
        --path = "",
	ssl_verify = false,
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.111 Safari/537.36"
        }
    })
    ngx.header["step"] = 3.1;
    -- 如果下载图片的时候异常了
    if not resp or resp.status >=300 then
        ngx.header["step"] = 3.2;
        ------ngx.header["down error"] = err;
        -- ngx.say("request error :", err)
        ngx.exit(404)
    else
        ngx.header["step"] = 3.3;
        if not is_dir(dir) then
            ngx.header["mkdir"] = "mkdir -p " .. dir;
            os.execute("mkdir -p " .. dir)
        end
        --响应体
        --------ngx.header["writefile"] = "true";
        ------ngx.header["ori_file_path"] = ori_file_path;
        writefile(ori_file_path, resp.body)
    end
    httpc:close()
    ------ngx.header["step"] = 3;
end


-- --第四步：生成小图

if not file_exists(ori_file_path) then
    ngx.header["step"] = 4;
    ngx.exit(500)
else
    ngx.header["step"] = 5;

    -- m1 定宽等比绽放，小于宽度不处理
    -- gm convert t.jpg -resize "300x100000>" -quality 30 output_1.jpg

    -- m2 等比绽放，裁剪，比较适合头象，logo之类的需要固定大小的展示
    -- gm convert sh.jpg -thumbnail "100x100^" -gravity center -extent 100x100 -quality 30 output_3.jpg

    -- m3 等比绽放，不足会产生白边
    -- gm convert sh.jpg -thumbnail "100x100" -gravity center -extent 100x100 -quality 30 output_3.jpg

    -- m9 无视参数宽 高 质量，由服务器固定图像质量，对质量进行压缩
    -- gm convert sh.jpg -quality 30 output_3.jpg

    local command = "";
    if (model == "m1") then
        command = "gm convert " .. ori_file_path
        .. " -resize \"" .. width .."x100000>\""
        .. " -background \"#fafafa\" "
        .. " -quality " .. quality .. " "
        .. min_file_path;
    elseif (model == "m2") then
        local size = width.."x"..height.."^";
        command = "gm convert " .. ori_file_path
        .. " -thumbnail \"" .. size .."^\" "
        .. " -gravity center "
        .. " -background \"#fafafa\" "
        .. " -extent " .. size
        .. " -quality " .. quality .. " "
        .. min_file_path;
    elseif (model == "m3") then
        local size = width.."x"..height;
        command = "gm convert " .. ori_file_path
        .. " -thumbnail " .. size .." "
        .. " -gravity center "
        .. " -background \"#fafafa\" "
        .. " -extent " .. size
        .. " -quality " .. quality .. " "
        .. min_file_path;
    elseif (model == "m9") then
        local length = length_of_file(ori_file_path)
        --ngx.header.length = length;
        if length > 1024*1024 then
            quality = 35
        elseif length > 100*1024 then
            quality = 65
        else
            quality = 90
        end
        local size = width.."x"..height;
        command = "gm convert " .. ori_file_path
        -- .. " -thumbnail " .. size .." "
        -- .. " -gravity center "
        -- .. " -background \"#fafafa\" "
        -- .. " -extent " .. size
        .. " -quality " .. quality .. " "
        .. min_file_path;
    end
    ngx.header.command = command;
    os.execute(command);
    length_c();
end


if file_exists(min_file_path) then
    ------ngx.header["step"] = 6;
    -- /imgservice/603/9eb/6039ebd7e2f78f755cccf47907174c00_100x100_m1
    local redirect = "/img_service/"..first.."/"..second.."/"..min_file_name;
    ------ngx.header["min_file_path"] = min_file_path;
    ------ngx.header["redirect"] = redirect;
    local res = ngx.location.capture(redirect)
    if res.status == 200 then
      ngx.print(res.body)
    end
    ngx.exit(200)
else
    ngx.header["step"] = 7;
    ngx.exit(404)
end