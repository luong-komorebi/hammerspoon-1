@import Foundation;
@import Cocoa;
@import Carbon;
@import LuaSkin;
@import WebKit;
#import <SocketRocket/SRWebSocket.h>

// Websocket userdata struct
typedef struct _webSocketUserData {
    int selfRef;
    void *ws;
} webSocketUserData;

#define getWsUserData(L, idx) (__bridge HSWebSocketDelegate *)((webSocketUserData *)lua_touserdata(L, idx))->ws;
static const char *WS_USERDATA_TAG = "hs.websocket";

static int refTable;

@interface HSWebSocketDelegate: NSObject<SRWebSocketDelegate>
@property int fn;
@property (strong) SRWebSocket *webSocket;
@end

@implementation HSWebSocketDelegate

- (instancetype)initWithURL:(NSURL *)URL {
    if((self = [super init])) {
        _webSocket = [[SRWebSocket alloc] initWithURL:URL];
        _webSocket.delegate = self;
    }
    return self;
}
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    if (self.fn == LUA_NOREF) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        LuaSkin *skin = [LuaSkin shared];
        _lua_stackguard_entry(skin.L);

        [skin pushLuaRef:refTable ref:self.fn];
        [skin pushNSObject:message];

        [skin protectedCallAndError:@"hs.websocket callback" nargs:1 nresults:0];
        _lua_stackguard_exit(skin.L);
    });
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
    NSLog(@"Websocket Connected");
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    NSLog(@":( Websocket Failed With Error %@", error);
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithString:(nonnull NSString *)string
{
    NSLog(@"Received \"%@\"", string);
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
{
    NSLog(@"WebSocket closed");
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;
{
    NSLog(@"WebSocket received pong");
}
@end

/// hs.websocket.new(url, callback) -> object
/// Function
/// Creates a new websocket connection.
///
/// Parameters:
///  * url - The URL to the websocket
///  * callback - A function returning a string for each recieved websocket message
///
/// Returns:
///  * The `hs.websocket` object
///
/// Notes:
///  * The callback is passed one string parameter containing the received message
///  * Given a path '/mysock' and a port of 8000, the websocket URL is as follows:
///   * ws://localhost:8000/mysock
///   * wss://localhost:8000/mysock (if SSL enabled)
static int websocket_new(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TSTRING, LS_TFUNCTION, LS_TBREAK];

    NSString *url = [skin toNSObjectAtIndex:1];
    HSWebSocketDelegate* ws = [[HSWebSocketDelegate alloc] initWithURL:[NSURL URLWithString:url]];

    lua_pushvalue(L, 2);
    ws.fn = [skin luaRef:refTable];

    [ws.webSocket open];

    webSocketUserData *userData = lua_newuserdata(L, sizeof(webSocketUserData));
    memset(userData, 0, sizeof(webSocketUserData));
    userData->ws = (__bridge_retained void*)ws;
    luaL_getmetatable(L, WS_USERDATA_TAG);
    lua_setmetatable(L, -2);

    return 1;
}

/// hs.websocket:send(message) -> object
/// Method
/// Sends a message to the websocket client
///
/// Parameters:
///  * message - A string containing the message to send
///
/// Returns:
///  * The `hs.websocket` object
static int websocket_send(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TUSERDATA, WS_USERDATA_TAG, LS_TSTRING, LS_TBREAK];
    HSWebSocketDelegate* ws = getWsUserData(L, 1);

    NSData *message = [skin toNSObjectAtIndex:2 withOptions: LS_NSLuaStringAsDataOnly];
    [ws.webSocket send:message];

    lua_pushvalue(L, 1);
    return 1;
}

/// hs.websocket:close() -> object
/// Method
/// Closes a websocket connection.
///
/// Parameters:
///  * None
///
/// Returns:
///  * The `hs.websocket` object
static int websocket_close(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TUSERDATA, WS_USERDATA_TAG, LS_TBREAK];
    HSWebSocketDelegate* ws = getWsUserData(L, 1);

    [ws.webSocket close];

    lua_pushvalue(L, 1);
    return 1;
}

static int websocket_gc(lua_State* L){
    webSocketUserData *userData = lua_touserdata(L, 1);
    HSWebSocketDelegate* ws = (__bridge_transfer HSWebSocketDelegate *)userData->ws;
    userData->ws = nil;

    [ws.webSocket close];
    ws.webSocket.delegate = nil;
    ws.webSocket = nil;
    ws.fn = [[LuaSkin shared] luaUnref:refTable ref:ws.fn];
    ws = nil;

    return 0;
}

static int websocket_tostring(lua_State* L) {
    HSWebSocketDelegate* ws = getWsUserData(L, 1);
    NSString *host = @"disconnected";
        
    if (ws.webSocket.readyState==1) {
        host = @"connected";
    }

    lua_pushstring(L, [[NSString stringWithFormat:@"%s: %@ (%p)", WS_USERDATA_TAG, host, lua_topointer(L, 1)] UTF8String]);
    return 1;
}

static const luaL_Reg websocketlib[] = {
    {"new",         websocket_new},
    
    {NULL, NULL} // This must end with an empty struct
};

static const luaL_Reg metalib[] = {
    {NULL, NULL} // This must end with an empty struct
};

static const luaL_Reg wsMetalib[] = {
    {"send",        websocket_send},
    {"close",       websocket_close},
    {"__tostring",  websocket_tostring},
    {"__gc",        websocket_gc},
    
    {NULL, NULL} // This must end with an empty struct
};

int luaopen_hs_websocket_internal(lua_State* L __unused) {
    LuaSkin *skin = [LuaSkin shared];

    refTable = [skin registerLibrary:websocketlib metaFunctions:metalib];
    [skin registerObject:WS_USERDATA_TAG objectFunctions:wsMetalib];
    
    return 1;
}
