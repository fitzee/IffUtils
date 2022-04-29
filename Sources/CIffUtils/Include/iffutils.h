//
//  Header.h
//  
//
//  Created by Matthew Fitzgerald on 15/4/2022.
//

#ifndef iffutils_h
#define iffutils_h

typedef struct {
    char type[4];
    unsigned int size;
    char subtype[4];
} IFFHeader;

typedef struct {
    char chunkType[4];
    unsigned int chunkSize;
} ChunkDesc;

typedef struct {
    unsigned short w, h;
    short x, y;
    char nPlanes;
    char masking;
    char compression;
    char padl;
    unsigned short transparentColor;
    char xAspect, yAspect;
    short pageW, pageH;
} BMHD;

typedef struct {
    short  pad1;
    short  rate;
    short  flags;
    char low, high;
} CRange;

typedef struct {
    short x, y;
} Point2D;

typedef struct {
   unsigned long viewModes;
} CamgChunk;

#endif /* iffutils_h */
