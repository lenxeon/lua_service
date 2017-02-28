_M = { _VERSION = "1.0" }

local reset = 0

-- 设计过期时间
local function expire_key(redis_connection, key, interval)
    local expire, error = redis_connection:expire(key, interval)
    ngx.header["interval"] = interval;
    if not expire then
        ngx.log(log_level, "failed to get ttl: ", error)
        return
    end
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

-- 策略逻辑，如何计数及返回该用户用了多少次，还可以请求多少次，下次重置时间
local function bump_request(redis_connection, redis_pool_size, ip_key, rate, interval, current_time, log_level)
    local key = "RL:" .. ip_key
    -- 给这个key增加一次计数
    local count, error = redis_connection:incr(key)
    -- 如果redis处理失败了
    if not count then
        ngx.log(log_level, "failed to incr count: ", error)
        return
    end
    -- 如果count==1表示是，该时间段第一次请求
    if tonumber(count) == 1 then
        reset = (current_time + interval)
        expire_key(redis_connection, key, interval)
    else
        local ttl, error = redis_connection:pttl(key)
        if not ttl then
            ngx.log(log_level, "failed to get ttl: ", error)
            return
        end
        if ttl == -1 then
            ttl = interval
            expire_key(redis_connection, key, interval)
        end
        reset = (current_time + (ttl * 0.001))
    end

    local ok, error = redis_connection:set_keepalive(60000, redis_pool_size)
    if not ok then
        ngx.log(log_level, "failed to set keepalive: ", error)
    end

    local remaining = rate - count

    return { count = count, remaining = remaining, reset = reset }
end

function _M.limit(config)
    local log_level = config.log_level or ngx.ERR
    ngx.log(log_level, "failed to require redis")
    ngx.header["step"] = model;

    -- 这一段为了控制是否是服务器维护模式
    if model == 'debug' and not self_addr then
        ngx.say('{"status_code":25,"status_message":"尊敬的用户您服务器正在维护,请稍后"}')
        ngx.exit(ngx.HTTP_OK)
    end

    -- 这一段表示不控制
    if model == 'release' then
        return
    end

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
    local ips = {"127.0.0.1"} --这儿设置自己的办公室的固定ip
    local self_addr = in_array(ngx.var.remote_addr, ips) --判断是否是允许范围内的ip

    local response, error = bump_request(connection, redis_pool_size, key, rate, interval, current_time, log_level)
    
    if not response then
        return
    end

    if response.count > rate then
        local retry_after = math.floor(response.reset - current_time)
        if retry_after < 0 then
            retry_after = 0
        end

        ngx.header["Access-Control-Allow-Origin"] = "*"
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.header["Retry-After"] = retry_after
        ngx.status = 429
        ngx.header["x-powered-by"] = "Express"
        ngx.say('{"status_code":25,"status_message":"Your request count (' .. response.count .. ') is over the allowed limit of ' .. rate .. '."}')
        ngx.exit(ngx.HTTP_OK)
    else
        ngx.header["Content-Type"] = "application/html; charset=utf-8"
        ngx.header["x-powered-by"] = "Express"
        --ngx.header["X-RateLimit-Limit"] = rate
        ngx.header["X-RateLimit-Remaining"] = math.floor(response.remaining)
        ngx.header["X-RateLimit-offset"] = math.floor(response.reset - ngx.now())
        ngx.header["X-RateLimit-Reset"] = math.floor(response.reset)
    end
end

return _M