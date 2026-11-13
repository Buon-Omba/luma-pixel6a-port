#!/usr/bin/env python3
# GL_RENDERER di un contesto EGL su GBM del dispositivo di display (card0). Solo test.
import ctypes as C, os, sys
fd = os.open(sys.argv[1] if len(sys.argv) > 1 else '/dev/dri/card0', os.O_RDWR)
gbm = C.CDLL('libgbm.so.1'); egl = C.CDLL('libEGL.so.1'); gl = C.CDLL('libGLESv2.so.2')
gbm.gbm_create_device.restype = C.c_void_p
dev = gbm.gbm_create_device(fd); assert dev, 'gbm_create_device'
gbm.gbm_device_get_backend_name.restype = C.c_char_p; gbm.gbm_device_get_backend_name.argtypes = [C.c_void_p]
print('gbm backend', gbm.gbm_device_get_backend_name(dev).decode())
egl.eglGetProcAddress.restype = C.c_void_p
gpd = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.c_void_p)(egl.eglGetProcAddress(b'eglGetPlatformDisplayEXT'))
dpy = gpd(0x31D7, C.c_void_p(dev), None)          # EGL_PLATFORM_GBM_KHR
egl.eglInitialize.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p]
assert egl.eglInitialize(dpy, None, None), 'eglInitialize'
egl.eglBindAPI(0x30A0)
egl.eglCreateContext.restype = C.c_void_p
egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
ctx = egl.eglCreateContext(dpy, None, None, (C.c_int * 3)(0x3098, 2, 0x3038))   # EGL_NO_CONFIG_KHR
egl.eglMakeCurrent.argtypes = [C.c_void_p] * 4
assert egl.eglMakeCurrent(dpy, None, None, ctx), 'eglMakeCurrent'
gl.glGetString.restype = C.c_char_p
print('RENDERER', gl.glGetString(0x1F01).decode())
