/// A minimal binding to the ONNX Runtime C API, for models sherpa-onnx does not
/// run itself (the Turkish EMA voice). It uses the ONNX Runtime library that
/// sherpa-onnx already ships, so the app carries no second copy.
///
/// Only CPU inference with float32 / int64 tensors is covered.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Positions in the OrtApi function table (onnxruntime_c_api.h). The table only
// ever grows at the end, so these hold for every ONNX Runtime version >= 1.14.
const _iGetErrorMessage = 2, _iCreateEnv = 3, _iCreateSession = 7, _iRun = 9, _iCreateSessionOptions = 10;
const _iSetOptLevel = 23, _iSetIntraThreads = 24, _iSetInterThreads = 25;
const _iCreateTensorWithData = 49, _iGetTensorMutableData = 51, _iGetDimensionsCount = 61, _iGetDimensions = 62;
const _iGetTensorTypeAndShape = 65, _iCreateCpuMemoryInfo = 69;
const _iReleaseStatus = 93, _iReleaseSession = 95, _iReleaseValue = 96, _iReleaseTypeAndShape = 99, _iReleaseSessionOptions = 100;
const _apiVersion = 14;

const _float = 1, _int64 = 7;

typedef _P = Pointer<Void>;
typedef _PP = Pointer<Pointer<Void>>;

class OrtError implements Exception {
  final String message;
  OrtError(this.message);
  @override
  String toString() => 'ONNX Runtime: $message';
}

/// One loaded ONNX Runtime (one per isolate).
class Ort {
  final _PP _api;
  Pointer<NativeFunction<T>> _f<T extends Function>(int i) => _api[i].cast<NativeFunction<T>>();

  late final _getErrorMessage = _f<Pointer<Utf8> Function(_P)>(_iGetErrorMessage).asFunction<Pointer<Utf8> Function(_P)>();
  late final _createEnv = _f<_P Function(Int32, Pointer<Utf8>, _PP)>(_iCreateEnv).asFunction<_P Function(int, Pointer<Utf8>, _PP)>();
  late final _createSession = _f<_P Function(_P, _P, _P, _PP)>(_iCreateSession).asFunction<_P Function(_P, _P, _P, _PP)>();
  late final _run = _f<_P Function(_P, _P, Pointer<Pointer<Utf8>>, _PP, Size, Pointer<Pointer<Utf8>>, Size, _PP)>(_iRun)
      .asFunction<_P Function(_P, _P, Pointer<Pointer<Utf8>>, _PP, int, Pointer<Pointer<Utf8>>, int, _PP)>();
  late final _createSessionOptions = _f<_P Function(_PP)>(_iCreateSessionOptions).asFunction<_P Function(_PP)>();
  late final _setOptLevel = _f<_P Function(_P, Int32)>(_iSetOptLevel).asFunction<_P Function(_P, int)>();
  late final _setIntraThreads = _f<_P Function(_P, Int32)>(_iSetIntraThreads).asFunction<_P Function(_P, int)>();
  late final _setInterThreads = _f<_P Function(_P, Int32)>(_iSetInterThreads).asFunction<_P Function(_P, int)>();
  late final _createTensorWithData = _f<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, _PP)>(_iCreateTensorWithData)
      .asFunction<_P Function(_P, _P, int, Pointer<Int64>, int, int, _PP)>();
  late final _getTensorMutableData = _f<_P Function(_P, _PP)>(_iGetTensorMutableData).asFunction<_P Function(_P, _PP)>();
  late final _getDimensionsCount = _f<_P Function(_P, Pointer<Size>)>(_iGetDimensionsCount).asFunction<_P Function(_P, Pointer<Size>)>();
  late final _getDimensions = _f<_P Function(_P, Pointer<Int64>, Size)>(_iGetDimensions).asFunction<_P Function(_P, Pointer<Int64>, int)>();
  late final _getTensorTypeAndShape = _f<_P Function(_P, _PP)>(_iGetTensorTypeAndShape).asFunction<_P Function(_P, _PP)>();
  late final _createCpuMemoryInfo = _f<_P Function(Int32, Int32, _PP)>(_iCreateCpuMemoryInfo).asFunction<_P Function(int, int, _PP)>();
  late final _releaseStatus = _f<Void Function(_P)>(_iReleaseStatus).asFunction<void Function(_P)>();
  late final _releaseSession = _f<Void Function(_P)>(_iReleaseSession).asFunction<void Function(_P)>();
  late final _releaseValue = _f<Void Function(_P)>(_iReleaseValue).asFunction<void Function(_P)>();
  late final _releaseTypeAndShape = _f<Void Function(_P)>(_iReleaseTypeAndShape).asFunction<void Function(_P)>();
  late final _releaseSessionOptions = _f<Void Function(_P)>(_iReleaseSessionOptions).asFunction<void Function(_P)>();

  late final _P _env;
  late final _P _mem;

  Ort._(this._api) {
    final logId = 'vocabloom'.toNativeUtf8();
    try {
      _env = _out((p) => _createEnv(3, logId, p)); // ORT_LOGGING_LEVEL_ERROR
    } finally {
      malloc.free(logId);
    }
    _mem = _out((p) => _createCpuMemoryInfo(1, 0, p)); // OrtArenaAllocator, OrtMemTypeDefault
  }

  static Ort? _instance;

  /// The ONNX Runtime next to sherpa-onnx; [libDir] is used by tests.
  static Ort load([String? libDir]) {
    if (_instance != null) return _instance!;
    final lib = _open(libDir);
    final getBase = lib.lookupFunction<_PP Function(), _PP Function()>('OrtGetApiBase');
    final getApi = getBase()[0].cast<NativeFunction<_PP Function(Uint32)>>().asFunction<_PP Function(int)>();
    final api = getApi(_apiVersion);
    if (api == nullptr) throw OrtError('API version $_apiVersion not available');
    return _instance = Ort._(api);
  }

  static DynamicLibrary _open(String? dir) {
    if (Platform.isAndroid) return DynamicLibrary.open('libonnxruntime.so');
    if (Platform.isLinux) return DynamicLibrary.open(dir == null ? 'libonnxruntime.so' : '$dir/libonnxruntime.so');
    if (Platform.isWindows) return DynamicLibrary.open(dir == null ? 'onnxruntime.dll' : '$dir\\onnxruntime.dll');
    return DynamicLibrary.process(); // Apple: linked into sherpa-onnx's framework
  }

  void _check(_P status) {
    if (status == nullptr) return;
    final msg = _getErrorMessage(status).toDartString();
    _releaseStatus(status);
    throw OrtError(msg);
  }

  _P _out(_P Function(_PP) f) {
    final p = calloc<Pointer<Void>>();
    try {
      _check(f(p));
      return p.value;
    } finally {
      calloc.free(p);
    }
  }

  /// Loads a model file; [threads] CPU threads for its operators.
  OrtSession session(String path, {int threads = 1}) {
    final opts = _out(_createSessionOptions);
    try {
      _check(_setIntraThreads(opts, threads));
      _check(_setInterThreads(opts, 1));
      _check(_setOptLevel(opts, 99)); // ORT_ENABLE_ALL
      final _P cPath = Platform.isWindows ? path.toNativeUtf16().cast() : path.toNativeUtf8().cast();
      try {
        return OrtSession._(this, _out((p) => _createSession(_env, cPath, opts, p)));
      } finally {
        malloc.free(cPath);
      }
    } finally {
      _releaseSessionOptions(opts);
    }
  }
}

/// A tensor: float32 or int64 data and its shape.
class Tensor {
  final List<int> shape;
  final Float32List? f32;
  final Int64List? i64;
  Tensor.float(Float32List this.f32, this.shape) : i64 = null;
  Tensor.int64(Int64List this.i64, this.shape) : f32 = null;
}

class OrtSession {
  final Ort _o;
  _P? _s;
  OrtSession._(this._o, this._s);

  /// Runs the model on [inputs] (by name) and returns [outputs] (by name, float32).
  Map<String, Tensor> run(Map<String, Tensor> inputs, List<String> outputs) {
    final s = _s;
    if (s == null) throw OrtError('session closed');
    final o = _o;
    final arena = Arena();
    final created = <_P>[];
    final outVals = arena<Pointer<Void>>(outputs.length);
    for (var j = 0; j < outputs.length; j++) {
      outVals[j] = nullptr;
    }
    try {
      final inNames = arena<Pointer<Utf8>>(inputs.length);
      final inVals = arena<Pointer<Void>>(inputs.length);
      var i = 0;
      for (final MapEntry(:key, :value) in inputs.entries) {
        inNames[i] = key.toNativeUtf8(allocator: arena);
        final shape = arena<Int64>(value.shape.length);
        for (var d = 0; d < value.shape.length; d++) {
          shape[d] = value.shape[d];
        }
        final _P data;
        final int bytes, type;
        if (value.f32 case final f?) {
          final p = arena<Float>(f.length);
          p.asTypedList(f.length).setAll(0, f);
          (data, bytes, type) = (p.cast(), f.length * 4, _float);
        } else {
          final l = value.i64!;
          final p = arena<Int64>(l.length);
          p.asTypedList(l.length).setAll(0, l);
          (data, bytes, type) = (p.cast(), l.length * 8, _int64);
        }
        final v = o._out((p) => o._createTensorWithData(o._mem, data, bytes, shape, value.shape.length, type, p));
        created.add(v);
        inVals[i++] = v;
      }
      final outNames = arena<Pointer<Utf8>>(outputs.length);
      for (var j = 0; j < outputs.length; j++) {
        outNames[j] = outputs[j].toNativeUtf8(allocator: arena);
      }
      o._check(o._run(s, nullptr, inNames, inVals, inputs.length, outNames, outputs.length, outVals));
      final result = <String, Tensor>{};
      for (var j = 0; j < outputs.length; j++) {
        final v = outVals[j];
        final info = o._out((p) => o._getTensorTypeAndShape(v, p));
        final List<int> shape;
        try {
          final n = arena<Size>();
          o._check(o._getDimensionsCount(info, n));
          final dims = arena<Int64>(n.value);
          o._check(o._getDimensions(info, dims, n.value));
          shape = [for (var d = 0; d < n.value; d++) dims[d]];
        } finally {
          o._releaseTypeAndShape(info);
        }
        final count = shape.fold(1, (a, b) => a * b);
        final data = o._out((p) => o._getTensorMutableData(v, p));
        result[outputs[j]] = Tensor.float(Float32List.fromList(data.cast<Float>().asTypedList(count)), shape);
      }
      return result;
    } finally {
      for (final v in created) {
        o._releaseValue(v);
      }
      for (var j = 0; j < outputs.length; j++) {
        if (outVals[j] != nullptr) o._releaseValue(outVals[j]);
      }
      arena.releaseAll();
    }
  }

  void close() {
    final s = _s;
    if (s == null) return;
    _o._releaseSession(s);
    _s = null;
  }
}
