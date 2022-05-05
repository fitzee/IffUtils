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
    
    public init() {}
    
    
    /// Uncompresses a run-length encoded byte buffer and returns the converted array
    ///
    /// - Parameters:
    ///     - byteData: A pointer to the data buffer ([UInt8]) that will be uncompressed.
    public static func uncompressBuffer(byteData: UnsafeRawBufferPointer.SubSequence) -> [UInt8] {
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
    ///     - bmhd: A BMHD struct defining the data buffer, i.e. width of bitmap, # of bitplanes etc.
    static let maskTable: [UInt8] = [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]
    static let bitTable: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80]

    public static func convertPlanarLine(src: UnsafeRawBufferPointer, bmhd: BMHD) throws -> [UInt8] {
        let width = UInt16(bigEndian: bmhd.w)
        let planes = UInt16(bmhd.nPlanes)
        let bytesPerRow = ((width + 15) >> 4) << 1;
        var ptr: UnsafeRawBufferPointer
        
        // if the image is 24bits (or 32), each line is 3 (or 4) times as big - i.e. 1 byte for each color component
        let bytesPerPixel = planes > 8 ? Int(planes>>3) : Int(1)
        
        // this array will hold the converted line
        var p: [UInt8] = Array(repeating: 0, count: Int(width)*Int(bytesPerPixel))
        var bitIdx: UInt16 = 0          // represents the index within bitTable
        var compIdx = 0                 // the component index (e.g. R, G, or B)
        
        for horPos in 0..<width {
            ptr = src
            compIdx = ((Int(horPos)+1)*bytesPerPixel)-bytesPerPixel

            for curPlane in 0..<planes {
                let _byte = byteFromBuffer(ptr, index: Int(horPos)>>3) & maskTable[Int(horPos) & 0x0007]
                // reset the bitTable index for 24bit images every 8 bits!
                bitIdx = ((curPlane << 1) & 0x000F) >> 1
                if _byte > 0 {
                    p[compIdx] |= bitTable[Int(bitIdx)]
                }

                compIdx = bitIdx == 7 ? compIdx+1 : compIdx

                ptr = UnsafeRawBufferPointer(rebasing: ptr.dropFirst(Int(bytesPerRow)))
            }
        }
 
        return p
    }
    

    /// Returns a single byte at a specific index within a given buffer
    ///
    /// - Parameters:
    ///     - pointer: a pointer to a buffer
    ///     - index: the position (offset) within the buffer where the byte will be retrieved.
    private static func byteFromBuffer(_ pointer: UnsafeRawBufferPointer, index: Int) -> UInt8 {
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
    private static func rawBytesToStruct<T>(ptr: UnsafeRawBufferPointer.SubSequence, toStruct: T) -> T {
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
    private static func charArrayToString<UInt8>(charArray: UInt8, charArrayLen: Int) -> NSString {
        precondition(charArrayLen > 0)

        return NSString(bytes: withUnsafeBytes(of: charArray) {
            Array($0.bindMemory(to: UInt8.self))
        }, length: charArrayLen, encoding: String.Encoding.ascii.rawValue) ?? ""
    }
    
    
    public static func processFile(fileURL: URL) throws -> CGImage? {
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
        var bmhd: BMHD? = nil
        
        while(moreChunks) {
            let offsetAndChunk = newOffset+chunkSize
            let nextChunk = rawBytesToStruct(ptr: fileBuffer.withUnsafeBytes { $0[newOffset..<newOffset+chunkSize] }, toStruct: ChunkDesc())
            let nextChunkSize = CUnsignedInt(bigEndian: nextChunk.chunkSize)
            let nextChunkType = charArrayToString(charArray: nextChunk.chunkType, charArrayLen: 4)
            
            switch nextChunkType {
            case "BMHD":
                bmhd = rawBytesToStruct(ptr: fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }, toStruct: BMHD())
                
            case "CMAP":
                let paletteData = fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }
                palette.append(contentsOf: paletteData)
    
            case "BODY":
                guard bmhd != nil else { return nil }   // can't possibly do anything else without a BMHD chunk
                
                let width = UInt16(bigEndian: bmhd!.w)
                let height = UInt16(bigEndian: bmhd!.h)
                let rowBytes = ((width + 15) >> 4) << 1;
                let nPlanes = bmhd!.nPlanes
                
                // create a "view" over the image data
                let imageData = fileBuffer.withUnsafeBytes { $0[offsetAndChunk..<offsetAndChunk+Int(nextChunkSize)] }
                
                if(bmhd?.compression == 1) {
                    decompedBuffer = uncompressBuffer(byteData: imageData)
                } else {
                    decompedBuffer.append(contentsOf: UnsafeRawBufferPointer(rebasing: imageData))
                }
                
                var decompPtr = decompedBuffer.withUnsafeBytes { $0[...] }
                
                // store the unpacked IFF image data here
                var byteArray: [UInt8] = [UInt8]()
                let offset = Int(rowBytes)*Int(bmhd!.nPlanes)
                
                for _ in 0..<height {
                    byteArray.append(contentsOf: try convertPlanarLine(src: UnsafeRawBufferPointer(rebasing: decompPtr), bmhd: bmhd!))
                    decompPtr = decompPtr.withUnsafeBytes { $0[offset...] }
                }
                
  
                // setup the bits we need to create a CGImage - it's mostly the same whether it's a "deep" or normal color-indexed ILBM (except for the colorSpace)
                let dp = CGDataProvider(data: CFDataCreate(kCFAllocatorDefault, byteArray, byteArray.count))
                let bmpinfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue)
                let indexedColorSpace = nPlanes <= 8 ? CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: palette.count / 3 - 1, colorTable: palette)! : CGColorSpaceCreateDeviceRGB()
                
                cgImg = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: (nPlanes > 8 ? Int(nPlanes) : 8), bytesPerRow: Int(width)*(nPlanes > 8 ? Int(nPlanes>>3) : Int(1)), space: indexedColorSpace, bitmapInfo: bmpinfo, provider: dp!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)

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
