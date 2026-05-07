"ui";
// 保持屏幕常亮
device.keepScreenOn();

// 导入OkHttp包
importPackage(Packages["okhttp3"]);


// const host = "ws://172.31.1.69:8080"; //本地内网
const host = "wss://device-cluster-dev.gyjxwh.com"; //开发环境
// const host = 'https://device-cluster.19ego.cn'; //生产环境

// 全局配置
const CONFIG = {
    WS_URL: host + "/websocket/device",  //ws地址
    HEARTBEAT_INTERVAL: 10000,  // 心跳间隔 10秒
    BASE_RECONNECT_DELAY: 1000, // 基础重连延迟 1秒
    MAX_RECONNECT_DELAY: 30000, // 最大重连延迟 30秒
    CONNECTION_TIMEOUT: 10000,  // 连接超时 10秒
    MAX_RECONNECT_ATTEMPTS: 0,  // 0表示无限重连
};

// 全局状态
const STATE = {
    client: null,
    webSocket: null,
    reconnectAttempts: 0,
    reconnectTimer: null,
    heartbeatTimer: null,
    heartbeatTimeoutTimer: null, // 心跳响应超时定时器
    lastHeartbeatResponse: 0,    // 最后一次心跳响应时间
    isConnected: false,
    networkReceiver: null,       // 网络广播接收器 
    scriptEngineExecute: null,          // 任务执行引擎
    engineCheckTimer: null,      // 引擎检查定时器
    curScriptContent: '',         // 当前脚本内容
    deviceInfo: {
        android_id: '',
        brand: '',
        product: '',
        ip: '',
        device_type: 0
    }
};

var autoxjsPkg = 'org.autojs.autoxjs.ozobi.v6';

// 判断设备是否已Root
function isRooted() {
    try {
        let result = shell("su -c 'exit'", true);
        return result.code === 0;
    } catch (e) {
        return false;
    }
}

// 获取本地IP地址
function getLocalIpAddress() {
    try {
        let wifiManager = context.getSystemService(context.WIFI_SERVICE);
        let wifiInfo = wifiManager.getConnectionInfo();
        let ipAddress = wifiInfo.getIpAddress();
        if (ipAddress == 0) {
            return "0.0.0.0"; // 无网络连接
        }
        return ((ipAddress & 0xFF) + "." +
            ((ipAddress >> 8) & 0xFF) + "." +
            ((ipAddress >> 16) & 0xFF) + "." +
            ((ipAddress >> 24) & 0xFF));
    } catch (e) {
        console.error("获取IP地址失败: " + e);
        return "0.0.0.0";
    }
}

// 生成随机UUID
function generateUUID() {
    // 定义十六进制字符
    const hexDigits = '0123456789abcdef';

    // 创建UUID模板 (符合RFC4122 v4标准)
    let uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';

    // 替换模板中的占位符
    uuid = uuid.replace(/[xy]/g, function (c) {
        // 生成随机数
        let r = Math.random() * 16 | 0;
        // 如果是'y'，则使用特定位模式 (8, 9, a, 或 b)
        let v = c === 'x' ? r : (r & 0x3 | 0x8);
        return hexDigits[v];
    });

    return uuid;
}


// 收集设备信息
function collectDeviceInfo() {
    try {
        STATE.deviceInfo.android_id = device.getAndroidId();
        STATE.deviceInfo.brand = device.brand;
        STATE.deviceInfo.product = device.product;
        STATE.deviceInfo.ip = getLocalIpAddress();
        STATE.deviceInfo.device_type = isRooted() ? 0 : 1;

        console.log("设备信息：", JSON.stringify(STATE.deviceInfo));
        return STATE.deviceInfo;
    } catch (e) {
        console.error("收集设备信息失败: " + e);
        // 确保即使出错也有基本信息
        if (!STATE.deviceInfo.android_id) {
            STATE.deviceInfo.android_id = "unknown";
        }
        return STATE.deviceInfo;
    }
}

// 更新UI状态
function updateUI() {
    ui.run(() => {
        try {
            ui.androidId.setText("Android ID: " + STATE.deviceInfo.android_id);
            ui.ipAddress.setText("内网IP: " + STATE.deviceInfo.ip);

            if (STATE.isConnected) {
                ui.connectionStatus.setText("连接状态: 已连接");
            } else if (STATE.reconnectTimer) {
                ui.connectionStatus.setText(`连接状态: 准备重连中...`);
            } else {
                ui.connectionStatus.setText("连接状态: 连接中...");
            }
        } catch (e) {
            console.error("更新UI失败: " + e);
        }
    });
}

{/* <button id="btnTest" text="测试字符串脚本" textColor="#ffffff" bg="#125252" marginBottom="16" />
     */}
// 创建UI界面
function createUI() {
    ui.layout(
        `<vertical padding="16">
            <text textSize="24sp" gravity="center" text="设备集群系统" marginBottom="16"/>
            <text id="androidId" textSize="16sp" text="Android ID: 加载中..." marginBottom="8"/>
            <text id="ipAddress" textSize="16sp" text="内网IP: 加载中..." marginBottom="8"/>
            <text id="wsAddress" textSize="16sp" text="WS地址: ${CONFIG.WS_URL}" marginBottom="8"/>
            <text id="connectionStatus" textSize="16sp" text="连接状态: 未连接" marginBottom="16" />

            <button id="closeBtn" text="关闭脚本" textColor="#ffffff" bg="#ff5252" marginBottom="16" />
        </vertical>`
    );

    // 更新UI
    updateUI();

    // 关闭按钮点击事件
    ui.closeBtn.click(() => {
        // 显示关闭确认对话框
        dialogs.confirm("确认关闭", "确定要关闭脚本吗？", (confirmed) => {
            if (confirmed) {
                console.log("用户关闭脚本");
                // 执行清理操作
                shutdownScript();
            }
        });
    });


    // ui.btnTest.click(() => {

    // });
}

// 更新连接状态
function updateConnectionStatus(status) {
    console.log("连接状态: " + status);

    ui.run(() => {
        ui.connectionStatus.setText("连接状态: " + status);
    });
}

// 格式化日期时间
function formatDateTime(timestamp) {
    let date = new Date(timestamp);
    let year = date.getFullYear();
    let month = String(date.getMonth() + 1).padStart(2, '0');
    let day = String(date.getDate()).padStart(2, '0');
    let hours = String(date.getHours()).padStart(2, '0');
    let minutes = String(date.getMinutes()).padStart(2, '0');
    let seconds = String(date.getSeconds()).padStart(2, '0');

    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}

// WebSocket监听器
const wsListener = {
    onOpen: function (webSocket, response) {
        console.log("WebSocket连接成功");
        STATE.reconnectAttempts = 0;
        STATE.isConnected = true;

        // 记录连接成功时间
        STATE.lastHeartbeatResponse = Date.now();

        // 发送设备信息
        try {
            let deviceInfoMsg = JSON.stringify(STATE.deviceInfo);
            webSocket.send(deviceInfoMsg);
            console.log("发送设备信息: " + deviceInfoMsg);
        } catch (e) {
            console.error("发送设备信息失败: " + e);
        }

        // 更新UI
        updateConnectionStatus("已连接");
        updateUI();

        // 启动心跳定时器
        startHeartbeat();

        // 清除重连定时器
        if (STATE.reconnectTimer) {
            clearTimeout(STATE.reconnectTimer);
            STATE.reconnectTimer = null;
        }
    },

    onMessage: function (webSocket, message) {
        try {
            // 更新最后一次响应时间
            STATE.lastHeartbeatResponse = Date.now();

            // 处理心跳响应
            if (message === "pong") {
                // 不显示心跳消息
                // console.log("收到心跳响应");
                return;
            }

            // 尝试解析JSON消息
            try {
                let data = JSON.parse(message);
                console.log("收到JSON消息: ", JSON.stringify(data));

                // 处理执行任务消息
                if (data.type === "executeTask" && data.script_content) {
                    STATE.curScriptContent = data.script_content;
                    handleExecuteTask();
                }
                // 处理停止脚本消息
                else if (data.type === "stopScript") {
                    handleStopScript();
                }
            } catch (e) {
                // 非JSON消息，作为普通文本处理
                console.log("收到普通文本消息");
            }
        } catch (e) {
            console.error("处理消息时出错: " + e);
        }
    },

    onClosing: function (webSocket, code, reason) {
        console.log("WebSocket正在关闭: 代码=" + code + ", 原因=" + reason);

        // 连接正在关闭，更新状态
        STATE.isConnected = false;

        // 更新UI状态
        updateConnectionStatus("正在断开...");

        // 提前准备重连，但不立即执行
        // 这样可以在onClosed触发前就做好重连准备，减少断开时间
        if (!STATE.reconnectTimer) {
            console.log("WebSocket正在关闭，准备重连");
            // 不立即清除心跳，等待onClosed完全触发
        }
    },

    onClosed: function (webSocket, code, reason) {
        console.log("WebSocket已关闭: 代码=" + code + ", 原因=" + reason);
        STATE.isConnected = false;
        STATE.webSocket = null;

        // 更新UI
        updateConnectionStatus("未连接");
        updateUI();

        // 停止心跳
        stopHeartbeat();

        // 始终尝试重连
        scheduleReconnect();
    },

    onFailure: function (webSocket, throwable, response) {
        console.error("WebSocket连接错误: " + throwable);
        STATE.isConnected = false;
        STATE.webSocket = null;

        // 更新UI状态
        updateConnectionStatus("连接错误");

        // 停止心跳
        stopHeartbeat();

        // 始终尝试重连
        scheduleReconnect();
    }
};

// 发送心跳
function startHeartbeat() {
    if (STATE.heartbeatTimer) {
        clearInterval(STATE.heartbeatTimer);
    }

    // 清除可能存在的心跳超时定时器
    if (STATE.heartbeatTimeoutTimer) {
        clearInterval(STATE.heartbeatTimeoutTimer);
    }

    // 启动心跳定时器
    STATE.heartbeatTimer = setInterval(() => {
        if (STATE.webSocket && STATE.isConnected) {
            try {
                // console.log("发送心跳: ping");
                STATE.webSocket.send("ping");
                // 心跳消息不添加到日志区域

            } catch (e) {
                console.error("心跳发送失败: " + e);
                // 心跳发送失败，可能连接已断开
                clearInterval(STATE.heartbeatTimer);
                STATE.heartbeatTimer = null;

                if (STATE.isConnected) {
                    STATE.isConnected = false;
                    STATE.webSocket = null;

                    // 更新UI
                    updateConnectionStatus("心跳失败");

                    // 立即尝试重连
                    connectWebSocket();
                }
            }
        } else {
            // 如果WebSocket已经不存在，停止心跳
            clearInterval(STATE.heartbeatTimer);
            STATE.heartbeatTimer = null;

            // 确保连接
            if (!STATE.isConnected && !STATE.reconnectTimer) {
                connectWebSocket();
            }
        }
    }, CONFIG.HEARTBEAT_INTERVAL);
}

// 停止心跳
function stopHeartbeat() {
    if (STATE.heartbeatTimer) {
        clearInterval(STATE.heartbeatTimer);
        STATE.heartbeatTimer = null;
    }

    if (STATE.heartbeatTimeoutTimer) {
        clearTimeout(STATE.heartbeatTimeoutTimer);
        STATE.heartbeatTimeoutTimer = null;
    }
}

// 连接WebSocket服务器
function connectWebSocket() {
    // 如果已经在连接中或已连接，则不重复连接
    if (STATE.isConnected || STATE.reconnectTimer) {
        return;
    }

    try {
        // 先清理之前可能存在的连接
        if (STATE.webSocket) {
            try {
                STATE.webSocket.close(1000, "重新连接");
            } catch (e) {
                console.error("关闭旧连接失败: " + e);
            }
            STATE.webSocket = null;
        }

        // 更新UI
        updateConnectionStatus("连接中...");

        // 创建OkHttp客户端，设置超时
        STATE.client = new OkHttpClient.Builder()
            .retryOnConnectionFailure(true)
            .connectTimeout(CONFIG.CONNECTION_TIMEOUT, java.util.concurrent.TimeUnit.MILLISECONDS)
            .readTimeout(CONFIG.CONNECTION_TIMEOUT, java.util.concurrent.TimeUnit.MILLISECONDS)
            .writeTimeout(CONFIG.CONNECTION_TIMEOUT, java.util.concurrent.TimeUnit.MILLISECONDS)
            .build();

        // 创建请求
        const request = new Request.Builder()
            .url(CONFIG.WS_URL)
            .build();

        // 清理之前的连接
        if (STATE.client && STATE.client.dispatcher()) {
            STATE.client.dispatcher().cancelAll();
        }

        // 创建WebSocket
        STATE.webSocket = STATE.client.newWebSocket(request, new WebSocketListener(wsListener));

    } catch (e) {
        console.error("连接WebSocket时出错: " + e);
        updateConnectionStatus("连接失败");

        // 尝试重连
        scheduleReconnect();
    }
}

// 使用指数退避算法进行重连
function scheduleReconnect() {
    // 如果已经设置了重连定时器，不重复设置
    if (STATE.reconnectTimer) {
        return;
    }

    // 检查是否超过最大重连次数（如果设置了限制）
    if (CONFIG.MAX_RECONNECT_ATTEMPTS > 0 && STATE.reconnectAttempts >= CONFIG.MAX_RECONNECT_ATTEMPTS) {
        console.log("已达到最大重连次数，停止重连");
        updateConnectionStatus("重连失败，将在网络变化时重试");
        return;
    }

    STATE.reconnectAttempts++;
    const delay = Math.min(
        CONFIG.BASE_RECONNECT_DELAY * Math.pow(1.5, Math.min(STATE.reconnectAttempts, 10)),
        CONFIG.MAX_RECONNECT_DELAY
    );

    console.log(`${delay / 1000}秒后尝试重连, 当前尝试次数: ${STATE.reconnectAttempts}`);

    updateConnectionStatus(`${delay / 1000}秒后重连`);

    // 清除之前的重连定时器
    if (STATE.reconnectTimer) {
        clearTimeout(STATE.reconnectTimer);
    }

    STATE.reconnectTimer = setTimeout(() => {
        STATE.reconnectTimer = null;
        connectWebSocket();
    }, delay);
}

// 关闭脚本并清理资源
function shutdownScript() {
    // 显示关闭中提示
    updateConnectionStatus("正在关闭...");

    // 执行清理操作
    cleanup();

    // 延迟一秒后退出，确保清理操作完成
    setTimeout(() => {
        try {
            engines.stopAll();
        } catch (err) {
            console.error("停止引擎出错: " + err);
        }
    }, 500);
}

// 清理资源
function cleanup() {
    console.log("开始清理资源...");

    // 停止所有脚本
    handleStopScript();

    // 停止心跳
    stopHeartbeat();

    // 清除所有可能存在的定时器
    try {
        // 清除重连定时器
        if (STATE.reconnectTimer) {
            clearTimeout(STATE.reconnectTimer);
            STATE.reconnectTimer = null;
            console.log("已清除重连定时器");
        }

        // 手动清理所有已知的定时器
        if (STATE.heartbeatTimer) {
            clearInterval(STATE.heartbeatTimer);
            STATE.heartbeatTimer = null;
            console.log("已清除心跳定时器");
        }

        if (STATE.heartbeatTimeoutTimer) {
            clearTimeout(STATE.heartbeatTimeoutTimer);
            STATE.heartbeatTimeoutTimer = null;
            console.log("已清除心跳超时定时器");
        }

        if (STATE.engineCheckTimer) {
            clearInterval(STATE.engineCheckTimer);
            STATE.engineCheckTimer = null;
            console.log("已清除引擎检查定时器");
        }

        console.log("已尝试清除所有定时器");
    } catch (e) {
        console.error("清除定时器出错: " + e);
    }

    // 关闭WebSocket连接
    if (STATE.webSocket) {
        try {
            STATE.webSocket.close(1000, "用户关闭脚本");
            console.log("已关闭WebSocket连接");
        } catch (e) {
            console.error("关闭WebSocket失败: " + e);
        }
        STATE.webSocket = null;
    }

    // 清理OkHttp资源
    if (STATE.client && STATE.client.dispatcher()) {
        try {
            STATE.client.dispatcher().cancelAll();
            console.log("已取消所有OkHttp请求");
        } catch (e) {
            console.error("取消OkHttp请求失败: " + e);
        }
    }

    // 注销网络广播接收器
    if (STATE.networkReceiver) {
        try {
            events.broadcast.unregisterReceiver(STATE.networkReceiver);
            console.log("网络广播接收器已注销");
        } catch (e) {
            console.error("注销网络广播接收器失败: " + e);
        }
    }

    console.log("资源清理完成");
}

// 处理执行任务消息
function handleExecuteTask() {
    console.log("收到执行任务请求");

    // 如果已有正在执行任务引擎，先停止它
    handleStopScript();

    sleep(3000);

    STATE.scriptEngineExecute = engines.execScript(generateUUID(), STATE.curScriptContent);
    if (STATE.webSocket && STATE.isConnected) {
        let successMsg = {
            type: "executeTaskSuccess",
            android_id: STATE.deviceInfo.android_id
        };
        let successMsgStr = JSON.stringify(successMsg);
        STATE.webSocket.send(successMsgStr);
        console.log("已发送任务执行成功消息");
    }

    // STATE.engineCheckTimer = setInterval(() => {
    //     if (STATE.scriptEngineExecute && STATE.scriptEngineExecute.getEngine().isDestroyed()) {
    //         console.log("引擎任务终止，开始重启任务");
    //         STATE.scriptEngineExecute = null;
    //         sleep(3000);
    //         STATE.scriptEngineExecute = engines.execScript(generateUUID(), STATE.curScriptContent);
    //     }
    // }, 6000);
}

// 处理停止脚本消息
function handleStopScript() {
    console.log("开始停止脚本引擎");
    if (STATE.scriptEngineExecute) {
        try {
            STATE.scriptEngineExecute.getEngine().emit('stopScript');
            if (!STATE.scriptEngineExecute.getEngine().isDestroyed()) {
                STATE.scriptEngineExecute.getEngine().forceStop();
            }
        } catch (e) {
            console.error("中断脚本引擎失败: " + e);
        }
    }
    cleanScriptEngine();
}

function cleanScriptEngine() {
    if (STATE.scriptEngineExecute) {
        STATE.scriptEngineExecute = null;
    }

    // 停止引擎检查定时器
    if (STATE.engineCheckTimer) {
        clearInterval(STATE.engineCheckTimer);
        STATE.engineCheckTimer = null;
    }

    console.log("脚本引擎已停止");
}

// 主函数
function main() {
    // 收集设备信息
    collectDeviceInfo();

    // 创建UI界面 (如果在UI模式下)
    createUI();

    // 连接WebSocket
    connectWebSocket();
}

// 启动脚本
main();
