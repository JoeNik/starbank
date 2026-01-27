方法下发接口文档
方法下发是一种配置下发模式：服务端返回请求配置，客户端自行请求上游平台。此类接口不消耗积分，适用于搜索、榜单、歌单等非核心功能。
一、接口列表
所有接口请求方式均为 GET
接口地址	接口功能
/v1/methods	获取所有平台及其可用方法概览
/v1/methods/:platform	获取指定平台的所有可用方法
/v1/methods/:platform/:function	获取指定平台指定功能的请求配置
二、可用方法（function）
| 方法名 | 功能描述 | 所需模板变量 || ---- | ---- || search | 搜索歌曲 | {{keyword}}, {{page}}, {{pageSize}} || toplists | 获取排行榜列表 | 无 || toplist | 获取排行榜详情 | {{id}} || playlist | 获取歌单详情 | {{id}} |
三、响应结构
服务端返回的配置对象包含以下字段，字段类型均为string（特殊标注除外）：
字段	类型	说明
type	string	请求类型，固定为 "http"
method	string	HTTP 方法：GET 或 POST
url	string	请求目标 URL
params	object	URL 查询参数，值中可能包含 {{变量}} 占位符
body	object	请求体（仅 POST 请求返回该字段）
headers	object	请求头
transform	string	可选，转换函数字符串
四、使用示例
以酷我平台搜索歌曲为例，演示完整调用流程
Step 1: 获取搜索方法配置
服务端返回的配置数据示例：
json
{
"code": 0,
"data": {
"type": "http",
"method": "GET",
"url": "http://search.kuwo.cn/r.s",
"params": {
"client": "kt",
"all": "",
"pn": "0",
"rn": "30"
},
"headers": { "User-Agent": "okhttp/4.9.0" },
"transform": "function(response) { ... }"
}
}
Step 2: 客户端替换模板变量并发起请求
前端代码实现示例（JavaScript）：
javascript
// 1. 获取方法配置
const res = await fetch('/api/v1/methods/kuwo/search');
const { data: config } = await res.json();

// 2. 替换模板变量
const params = {};
for (const [key, value] of Object.entries(config.params)) {
params[key] = value
.replace('', '周杰伦')
.replace('0', '0');
}

// 3. 发起请求
const url = new URL(config.url);
url.search = new URLSearchParams(params);
const response = await fetch(url, {
method: config.method,
headers: config.headers
});