_M = { _VERSION = "1.0" }

local http = require("resty.http")
local cjson = require("cjson")
local users = {"62546", "62547", "62548", "62549", "62545"}
local args = nil --参数集
local token = nil --用户的token



local function is_empty(s)
    if not s or type(s) ~= 'string' then
        return true
    end
    return s == nil or s == '' or s == 'null' or s == null
end

-- 设计过期时间
local function expire_key(redis_connection, key, interval)
    local expire, error = redis_connection:expire(key, interval)
    ngx.header["interval"] = interval
    if not expire then
        ngx.log(log_level, "failed to get ttl: ", error)
        return
    end
end

-- 设计过期时间
local function get_key(redis_connection, key)
    local result, error = redis_connection:get(key)
    ngx.header["interval"] = interval
    if not result then
        ngx.log(log_level, "failed to get ttl: ", error)
        return nil
    end
    return result
end

--判断一个值在不在数组中
local function in_array(b,list)
    if not list then
        return false 
    else
        for k, v in pairs(list) do
            if v == b then
                return true
            end
        end
        return false
    end
end


--根据用户的token获取用户的信息
local function get_user(redis_connection, token)
    local user_id = get_key(redis_connection, token)
    -- 先中缓存中找用户
    if not is_empty(user_id) then
        -- ngx.say(type(user_id))
        -- ngx.exit(ngx.HTTP_OK)
        -- ngx.header["user_id"] = user_id
        return user_id
    end
    --创建http客户端实例
    local httpc = http.new()
    local url = 'http://app01.yugusoft.com/ftask/proxy/user/my.json?token=' .. token
    -- ngx.exit(200)
    -- ngx.header["step"] = url

    local resp, err = httpc:request_uri(url, {
        method = "GET",
        --path = "",
        ssl_verify = false,
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.111 Safari/537.36"
        }
    })
    -- ngx.header["step"] = err
    -- ngx.header["step"] = resp.status
    -- 如果下载图片的时候异常了
    if not resp or resp.status >=300 then
        ngx.header["content-Type"] = "application/json"
        ngx.say('{"result":500,"msg":"调用获取用户的信息失败，请重新登陆"}')
        ngx.exit(200) -- 这儿为了和客户端的处理方式统一
    else
        local data = cjson.decode(resp.body)


        -- ngx.header["content-Type"] = "application/json"
        -- ngx.say(resp.body)
        -- ngx.exit(200) -- 这儿为了和客户端的处理方式统一

        if (data.result ~= 0) then
            ngx.header["content-Type"] = "application/json"
            ngx.say('{"result":500,"msg":"调用获取用户的信息失败，请重新登陆"}')
            ngx.exit(200) -- 这儿为了和客户端的处理方式统一
        end

        local user = data.user
        user_id = user.id
        -- ngx.say(user_id)
        -- ngx.exit(ngx.HTTP_OK)
        -- 给这个key增加一次计数
        local result, error = redis_connection:set(token, user_id)
        -- 如果redis处理失败了
        if not result then
            ngx.log(log_level, "failed to incr count: ", error)
            return
        end
        expire_key(redis_connection, token, 60*60)
        return user_id
    end
    httpc:close()
end 


-- -- 策略逻辑，如何计数及返回该用户用了多少次，还可以请求多少次，下次重置时间
-- local function bump_request(redis_connection, redis_pool_size, ip_key, rate, interval, current_time, log_level)
--     local key = "RL:" .. ip_key
--     -- 给这个key增加一次计数
--     local count, error = redis_connection:incr(key)
--     -- 如果redis处理失败了
--     if not count then
--         ngx.log(log_level, "failed to incr count: ", error)
--         return
--     end
--     -- 如果count==1表示是，该时间段第一次请求
--     if tonumber(count) == 1 then
--         reset = (current_time + interval)
--         expire_key(redis_connection, key, interval)
--     else
--         local ttl, error = redis_connection:pttl(key)
--         if not ttl then
--             ngx.log(log_level, "failed to get ttl: ", error)
--             return
--         end
--         if ttl == -1 then
--             ttl = interval
--             expire_key(redis_connection, key, interval)
--         end
--         reset = (current_time + (ttl * 0.001))
--     end

--     local ok, error = redis_connection:set_keepalive(60000, redis_pool_size)
--     if not ok then
--         ngx.log(log_level, "failed to set keepalive: ", error)
--     end

--     local remaining = rate - count

--     return { count = count, remaining = remaining, reset = reset }
-- end

function _M.limit(config)
    local log_level = config.log_level or ngx.ERR
    --ngx.log(log_level, "failed to require redis")
    ngx.header["step"] = 2

    -- 下面这一段主要目的为获取参数
    args = nil 
    token = nil
    local request_method = ngx.var.request_method
    if "GET" == request_method then
        args = ngx.req.get_uri_args()
    elseif "POST" == request_method then
        ngx.req.read_body()
        args = ngx.req.get_post_args()
    end
    token = args["token"]

    -- 下面这一段主要目的为首次初始化redis的连接
    if not config.connection then
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(log_level, "failed to require redis")
            return
        end

        local redis_config = config.redis_config or {}
        redis_config.timeout = redis_config.timeout or 1
        redis_config.host = redis_config.host or "127.0.0.1"
        redis_config.port = redis_config.port or 6379
        redis_config.pool_size = redis_config.pool_size or 100

        local redis_connection = redis:new()
        redis_connection:set_timeout(redis_config.timeout * 1000)

        local ok, error = redis_connection:connect(redis_config.host, redis_config.port)
        if not ok then
            ngx.log(log_level, "failed to connect to redis: ", error)
            return
        end
        config.redis_config = redis_config
        config.connection = redis_connection
    end


    local current_time = ngx.now()
    local connection = config.connection
    local redis_pool_size = config.redis_config.pool_size
    local key = config.key or ngx.var.remote_addr --ip
    local rate = config.rate or 10 --连接数限制
    local interval = config.interval or 1 --刷新时间间隔
    local model = config.model or ngx.var.model -- 运行模式
    local ips = {"192.168.11.3"} --这儿设置自己的办公室的固定ip
    local self_addr = in_array(ngx.var.remote_addr, ips) --判断是否是允许范围内的ip

    -- 这一段为了控制是否是服务器维护模式,备用
    if model == 'debug' and not self_addr then
        ngx.header["content-Type"] = "application/json"
        ngx.say('{"status_code":25,"status_message":"服务器正在维护，时间：2016-06-21 18:00 - 2016-07-01 08:00"}')
        ngx.exit(ngx.HTTP_OK)
    end
    ngx.header["step"] = 3
    ngx.header["ip"] = key
    ngx.header["user-id"] = user_id

    local user_id = get_user(connection, token)

    if not (in_array(user_id, users)) then
        ngx.header["content-Type"] = "application/json"
        ngx.say('{"result":500,"msg":"您的账户不在可外部使用员工之列"}')
        ngx.exit(200)
    else
        ngx.header["pass"] = "true"
    end


    -- local response, error = bump_request(connection, redis_pool_size, key, rate, interval, current_time, log_level)
    
    -- if not response then
    --     return
    -- end

    -- if response.count > rate then
    --     -- 如果能登陆
    --     ngx.header["Access-Control-Allow-Origin"] = "*"
    --     ngx.header["Content-Type"] = "application/json; charset=utf-8"
    --     -- ngx.header["Retry-After"] = retry_after
    --     ngx.status = 429
    --     ngx.header["x-powered-by"] = "Express"
    --     ngx.say('{"status_code":25,"status_message":"Your request count (' .. response.count .. ') is over the allowed limit of ' .. rate .. '."}')
    --     ngx.exit(ngx.HTTP_OK)
    -- else
    --     ngx.header["x-powered-by"] = "Express"
    -- end
end

return _M