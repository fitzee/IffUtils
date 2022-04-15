import CoreFoundation
import CoreData

public class IffUtils {
    private struct IFFHeader {
        var IFFType = UnsafeMutablePointer<CChar>.allocate(capacity: 4)
        var IFFSize: CUnsignedLong
        var IFFsubType = UnsafeMutablePointer<CChar>.allocate(capacity: 4)
    }
    
    private struct BMHD {
        var w, h: CUnsignedInt
        var nPlanes: CChar
        var masking: CChar
        var compression: CChar
        var padL: CChar
        var transparentColor: CUnsignedInt
        var xAspect, yAspect: CChar
        var pageW, pageH: CInt
    }
    
    public init() {}
    
    public static func m2i(l: CLong) -> CLong {
        return (((l & 0xff000000) >> 24) +
                ((l & 0x00ff0000) >> 8) +
                ((l & 0x0000ff00) << 8) +
                ((l & 0x000000ff) << 24))
    }
    
    public static func m2i(n: CInt) -> CInt {
        return (((n & 0xff00) >> 8) | ((n & 0x00ff) << 8))
    }
    
    public static func openIFF(fileURL: URL) -> [UInt8] {
        var fileBuffer = [UInt8]()
        
        do {
            let data = try Data(contentsOf: fileURL)
            var buf = [UInt8](repeating: 0, count: data.count)
            data.copyBytes(to: &buf, count: data.count)
            fileBuffer = buf
        } catch {
            // do something
        }
        
        return fileBuffer
    }
}
