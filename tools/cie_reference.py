"""Independent LittleCMS mapping for PDF calibrated-color test fixtures."""
import ctypes as c
import ctypes.util

class XYZ(c.Structure):
    _fields_=[('X',c.c_double),('Y',c.c_double),('Z',c.c_double)]
def reference(kind,params,values):
    # PDF's source-domain equations, followed by LittleCMS's independent
    # Bradford adaptation and unoptimized XYZ-to-sRGB transform (no BPC).
    lib=c.CDLL(ctypes.util.find_library('lcms2') or '/opt/homebrew/lib/liblcms2.dylib')
    signatures={
        'cmsCreateXYZProfile':([],c.c_void_p), 'cmsCreate_sRGBProfile':([],c.c_void_p),
        'cmsCreateTransform':([c.c_void_p,c.c_uint32,c.c_void_p,c.c_uint32,c.c_uint32,c.c_uint32],c.c_void_p),
        'cmsDoTransform':([c.c_void_p,c.c_void_p,c.c_void_p,c.c_uint32],None),
        'cmsDeleteTransform':([c.c_void_p],None),'cmsCloseProfile':([c.c_void_p],c.c_int),
        'cmsD50_XYZ':([],c.POINTER(XYZ)),
        'cmsAdaptToIlluminant':([c.POINTER(XYZ)]*4,c.c_int),
    }
    for name,(args,result) in signatures.items():
        f=getattr(lib,name);f.argtypes=args;f.restype=result
    source=lib.cmsCreateXYZProfile();target=lib.cmsCreate_sRGBProfile()
    transform=lib.cmsCreateTransform(source,(1<<22)|(9<<16)|(3<<3),target,(1<<22)|(4<<16)|(3<<3),1,0x0100)
    assert source and target and transform
    white=XYZ(*params['WhitePoint']); output=[]
    try:
        for value in values:
            if kind=='/CalGray':
                v=max(0,min(1,value[0]))**params.get('Gamma',1)
                xyz=[w*v for w in params['WhitePoint']]
            elif kind=='/CalRGB':
                linear=[max(0,min(1,v))**g for v,g in zip(value,params.get('Gamma',[1]*3))]
                matrix=params.get('Matrix',[1,0,0,0,1,0,0,0,1])
                xyz=[sum(matrix[i+3*j]*linear[j] for j in range(3)) for i in range(3)]
            else:
                ranges=[0,100]+params.get('Range',[-100,100,-100,100])
                l,a,b=[max(ranges[i*2],min(ranges[i*2+1],v)) for i,v in enumerate(value)]
                m=(l+16)/116
                xyz=[w*(t**3 if t>=6/29 else 108/841*(t-4/29)) for w,t in zip(params['WhitePoint'],[m+a/500,m,m-b/200])]
            adapted=XYZ();assert lib.cmsAdaptToIlluminant(c.byref(adapted),c.byref(white),lib.cmsD50_XYZ(),c.byref(XYZ(*xyz)))
            result=(c.c_double*3)();lib.cmsDoTransform(transform,c.byref(adapted),result,1)
            output.append([round(max(0,min(1,v))*255) for v in result])
        return output
    finally:
        lib.cmsDeleteTransform(transform);lib.cmsCloseProfile(source);lib.cmsCloseProfile(target)
