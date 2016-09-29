local request_method = ngx.var.request_method
local args = nil
if "GET" == request_method then
    args = ngx.req.get_uri_args()
else
    ngx.req.read_body()
    args = ngx.req.get_post_args()
end

local url = tostring(args["url"])

local http = require("resty.http")
    --创建http客户端实例
    local httpc = http.new()

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
    if not resp or resp.status >=300 then
        ngx.header["step"] = 3.2;
        ngx.exit(404)
    else
        ngx.header["step"] = 3.3;
        ngx.say(resp.body)
    end
    httpc:close()