# IffUtils - class for converting an IFF ILBM file to an NSImage

I wanted a decent IFF viewer for my Mac, but the only options were:
  * paying for a crappy app that was slow and didn't support 24bit images
  * using something heavyweight like Gimp with a plugin

Secondly, at the time I was quite interested in learning Swift; so decided to write my own viewer.
This is my attempt at that, it works fine, but the Swift code is probably not ideal/perfect.

I think I wanted to add some more features such as writing to other formats, but now that you
have an NSImage, there are plenty of other libraries out there that can do that kind of stuff.

Todo: add support for going the other way, i.e. NSImage to an IFF ILBM

# Usage
```
let iffProcessor = IffUtils()
let nsImage = NSImage(cgImage: try iffProcessor.processFile(fileURL: fileName!)!, size: CGSize.zero)
```

You can then do whatever you want with the resulting NSImage!
