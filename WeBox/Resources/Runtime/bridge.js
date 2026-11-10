// iOS host transport. Native sync errors must become catchable JS exceptions.
var __pendingNative = new Map();
var __nativeSequence = 0;
function __nativeSync(raw) {
  var result = __hostSync(raw), parsed = JSON.parse(result);
  if (parsed && parsed.__hostError) throw new Error(parsed.__hostError);
  return result;
}
function __nativeAsync(raw) {
  return new Promise(function(resolve) {
    var id = String(++__nativeSequence);
    __pendingNative.set(id, resolve);
    __hostRequest(id, raw);
  });
}
function __resolveNative(id, result) {
  var resolve = __pendingNative.get(id);
  __pendingNative.delete(id);
  if (resolve) resolve(result);
}
function __invokeIOS(id, name, args) {
  Promise.resolve().then(function() { return __weboxInvoke(name, args); })
    .then(function(value) { __hostComplete(id, value, ''); })
    .catch(function(error) { __hostComplete(id, '', String(error && error.message || error)); });
}
