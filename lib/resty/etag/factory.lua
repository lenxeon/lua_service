_M = { _VERSION = "1.0" }

local request_uri = ngx.var.uri

function _M.limit(config)
    ngx.header["step"] = 2;
    ngx.header["etag1"] = request_uri
    ngx.header["etag2"] = "a".."$uri"
end

return _M