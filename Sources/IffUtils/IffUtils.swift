import CoreFoundation
import CoreData
import CIffUtils
import CoreImage
import SwiftUI


public class IffUtils {
    enum IffUtilsError: Error {
        case invalidFile
        case fileError
        case unsupportedChunk
        case corruptFile
    }
    
    private struct BitmapInfo {
        var width, height, transparentColor, planes: Int
        var pageWidth, pageHeight: Int16
        var _masking: masking
        var compression: Bool
        var xAspect, yAspect: UInt8
        lazy var bytesPerRow: Int = Int(((width + 15) >> 4) << 1)
        lazy var bytesPerPixel: Int = Int(planes > 8 ? planes>>3 : 1)
        lazy var bitsPerPixel: Int = Int(bytesPerPixel*8)
        
        enum masking: UInt8 {
            case mskNone = 0, mskHasMask, mskHasTransparentColor, mskLasso
        }
        
        init(bmhd: BMHD) {
            self.width = Int(UInt16(bigEndian: bmhd.w))
            self.height = Int(UInt16(bigEndian: bmhd.h))
            self.planes = Int(bmhd.nPlanes)
            self.transparentColor = Int(UInt16(bigEndian: bmhd.transparentColor))
            self.pageWidth = Int16(bigEndian: bmhd.pageW)
            self.pageHeight = Int16(bigEndian: bmhd.pageH)
            self._masking = masking(rawValue: UInt8(bitPattern: bmhd.masking)) ?? masking.mskNone
            self.xAspect = UInt8(bitPattern: bmhd.xAspect)
            self.yAspect = UInt8(bitPattern: bmhd.yAspect)
            self.compression = bmhd.compression == 1 ? true : false
        }
    }

    private var bmpDetails: bitmapInfo? = nil
    
    public init() {}
    
    
    /// Uncompresses a run-length encoded byte buffer and returns the converted array
    ///
    /// - Parameters:
    ///     - byteData: A pointer to the data buffer ([UInt8]) that will be uncompressed.
    private func uncompressBuffer(byteData: UnsafeRawBufferPointer.SubSequence) -> [UInt8] {
        var uncompedBuffer = [UInt8]()
        let ptr =  UnsafeRawBufferPointer(rebasing: byteData)
        var i: Int? = 0
        
        while let i2 = i, i2 < byteData.count {
            let byte = byteFromBuffer(ptr, index: i!)
            let n = Int16(Int8(bitPattern: byte))
            
            if n >= 0 && n <= 127 {
                for _ in 0..<n+1 {
                    i! += 1
                    if(i! < byteData.count) {
                        uncompedBuffer.append(byteFromBuffer(ptr, index: i!))
                    }
                }
                
                i! += 1
                continue
            }
            
            if n >= -127 && n <= -1 {
                for _ in 0..<abs(n)+1 {
                    uncompedBuffer.append(byteFromBuffer(ptr, index: i!+1))
                }
                
                i! += 2
                continue
            }
            
            if n == -128 {
                i! += 2
                continue
            }
            
        }
        
        return uncompedBuffer
    }

    
    /// Converts a given buffer of bytes predicated by a defined BMHD struct from raster/planar format to a either a color-index format or an RGB value;
    /// the output is an array of bytes representing a single line of the bitmap that has been converted
    ///
    /// - Parameters:
    ///     - src: A pointer to the data buffer ([UInt8]) that will be converted.
    private let maskTable: [UInt8] = [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]
    private let bitTable: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80]

    private func convertPlanarLine(src: UnsafeRawBufferPointer) throws -> [UInt8] {
        precondition(bmpDetails != nil)
    
        var ptr: UnsafeRawBufferPointer
                
        // this array will hold the converted line
        var p: [UInt8] = Array(repeating: 0, count: bmpDetails!.width*bmpDetails!.bytesPerPixel)
        var bitIdx: Int = 0                  // represents the index within bitTable
        var compIdx: Int = 0                 // the component index (e.g. R, G, or B)
        
        for horPos in 0..<bmpDetails!.width {
            ptr = src
            compIdx = ((horPos+1)*bmpDetails!.bytesPerPixel)-bmpDetails!.bytesPerPixel

            for curPlane in 0..<bmpDetails!.planes {
                let _byte = byteFromBuffer(ptr, index: horPos>>3) & maskTable[horPos & 0x0007]
                // reset the bitTable index for 24bit images every 8 bits!
                bitIdx = ((curPlane << 1) & 0x000F) >> 1
                if _byte > 0 {
                    p[compIdx] |= bitTable[bitIdx]
                }

                compIdx = bitIdx == 7 ? compIdx+1 : compIdx
                ptr = UnsafeRawBufferPointer(rebasing: ptr.dropFirst(bmpDetails!.bytesPerRow))
            }
        }
 
        return p
    }
    

    /// Returns a single byte at a specific index within a given buffer
    ///
    /// - Parameters:
    ///     - pointer: a pointer to a buffer
    ///     - index: the position (offset) within the buffer where the byte will be retrieved.
    private func byteFromBuffer(_ pointer: UnsafeRawBufferPointer, index: Int) -> UInt8 {
        precondition(index >= 0)
        precondition(index <= pointer.count - MemoryLayout<UInt8>.size)

        var value = UInt8()
        withUnsafeMutableBytes(of: &value) { valuePtr in
            valuePtr.copyBytes(from: UnsafeRawBufferPointer(start: pointer.baseAddress!.advanced(by: index),
                                                            count: MemoryLayout<UInt8>.size))
        }
        return value
    }
    
    
    /// Returns a defined struct of type T from a sequence of bytes
    ///
    /// - Parameters:
    ///     - ptr: A pointer to the sequence of bytes to coerce into the struct.
    ///     - toStruct: an instance of T to contain the bytes.
    private func rawBytesToStruct<T>(ptr: UnsafeRawBufferPointer.SubSequence, toStruct: T) -> T {
        precondition(ptr.count == MemoryLayout<T>.size)
        
        let _data = Data(bytes: UnsafeRawBufferPointer(rebasing: ptr).baseAddress!, count: ptr.count)
        let t: T = _data.withUnsafeBytes { $0.load(as: T.self) }
        return t
    }
    
    
    /// Returns an NSString from a Swift representation of a C-like character array that may, or may not be NULL terminated
    ///
    /// - Parameters:
    ///     - charArray: A pointer to the character/byte array.
    ///     - charArrayLen: The number of characters/bytes in the array that should be included in the new NSString
    private func charArrayToString<UInt8>(charArray: UInt8, charArrayLen: Int) -> NSString {
        precondition(charArrayLen > 0)

        return NSString(bytes: withUnsafeBytes(of: charArray) {
            Array($0.bindMemory(to: UInt8.self))
        }, length: charArrayLen, encoding: String.Encoding.ascii.rawValue) ?? ""
    }
    
    
    public func processFile(fileURL: URL) throws -> CGImage? {
        var fileBuffer = [UInt8]()
        var decompedBuffer = [UInt8]()
        var palette = [UInt8]()
        var cgImg: CGImage? = nil
        
        do {
            let data = try Data(contentsOf: fileURL)
            var buf = [UInt8](repeating: 0, count: data.count)
            data.copyBytes(to: &buf, count: data.count)
            fileBuffer = buf
        } catch {
            throw IffUtilsError.invalidFile
        }
        
        let headerSize = MemoryLayout<IFFHeader>.size
        let chunkSize = MemoryLayout<ChunkDesc>.size
        
        // get the IFF header object
        let header: IFFHeader = fileBuffer.withUnsafeBytes { $0.load(as: IFFHeader.self) }
  
        // we only care about bitmap files
        let headerSubType = charArrayToString(charArray: header.subtype, charArrayLen: 4)
        if headerSubType != "ILBM" && headerSubType != "PBM " {
            throw IffUtilsError.invalidFile
        }
        
        var moreChunks = true
        var newOffset = headerSize
        
        while(moreChunks) {
            let offsetAndChunk = newOffset+chunkSize
            let nextChunk = rawBytesToStruct(ptr: fileBuffer.withUnsafeBytes { $0[newOffset..<newOffset+chunkSize] }, toStruct: ChunkDesc())
            let nextChunkSize = CUnsignedInt(bigEndian: nextChunk.chunkSize)
            let nextChunkType = charArrayToString(charArray: nextChunk.chunkType, charArrayLen: 4)
            
            switch nextChunkType {
            case "BMHD":
                bmpDetails = BitmapInfo(bmhd: rawBytesToStruct(ptr: fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }, toStruct: BMHD()))
                
            case "CMAP":
                let paletteData = fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }
                palette.append(contentsOf: paletteData)
    
            case "BODY":
                guard bmpDetails != nil else { return nil }   // can't possibly do anything else without a BMHD chunk
                
                // create a "view" over the image data
                let imageData = fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }
                
                if(bmpDetails!.compression) {
                    decompedBuffer = uncompressBuffer(byteData: imageData)
                } else {
                    decompedBuffer.append(contentsOf: UnsafeRawBufferPointer(rebasing: imageData))
                }
                
                var decompPtr = decompedBuffer.withUnsafeBytes { $0[...] }
                
                // store the unpacked IFF image data here
                var byteArray: [UInt8] = [UInt8]()
                let offset = bmpDetails!.bytesPerRow*bmpDetails!.planes
                
                for _ in 0..<bmpDetails!.height {
                    byteArray.append(contentsOf: try convertPlanarLine(src: UnsafeRawBufferPointer(rebasing: decompPtr)))
                    decompPtr = decompPtr.withUnsafeBytes { $0[offset...] }
                }
                
                // setup the bits we need to create a CGImage - it's mostly the same whether it's a "deep" or normal color-indexed ILBM (except for the colorSpace)
                let dp = CGDataProvider(data: CFDataCreate(kCFAllocatorDefault, byteArray, byteArray.count))
                let bmpinfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue)
                let indexedColorSpace = bmpDetails!.planes <= 8 ? CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: palette.count / 3 - 1, colorTable: palette)! : CGColorSpaceCreateDeviceRGB()
                
                cgImg = CGImage(width: bmpDetails!.width, height: bmpDetails!.height, bitsPerComponent: 8, bitsPerPixel: bmpDetails!.bitsPerPixel, bytesPerRow: Int(bmpDetails!.width)*bmpDetails!.bytesPerPixel, space: indexedColorSpace, bitmapInfo: bmpinfo, provider: dp!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)

                
                print(cgImg.debugDescription)
                
            // not supporting these chunk types right now
            case "CRNG", "CAMG", "GRAB", "DPPS", "ANNO", "DPI ":
                break
            
            default:
                throw IffUtilsError.unsupportedChunk
            }
            
            newOffset += (chunkSize + Int(nextChunkSize))
            if (newOffset % 2) == 1 {   // check for unpadded file
                newOffset += 1
            }
            
            if newOffset == fileBuffer.count {
                moreChunks = false      // at the end of the file, so let's get out of here
            }
        }

        return cgImg
    }

}
