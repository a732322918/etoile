#ifndef __LUCENE_INDEX_TERM_VECTORS_WRITER__
#define __LUCENE_INDEX_TERM_VECTORS_WRITER__

#include <Foundation/Foundation.h>

#define STORE_POSITIONS_WITH_TERMVECTOR 0x1
#define STORE_OFFSET_WITH_TERMVECTOR 0x2
#define TERM_VECTORS_WRITER_FORMAT_VERSION 2L
#define TERM_VECTORS_WRITER_FORMAT_SIZE 4L

static NSString *TVX_EXTENSION = @"tvx";
static NSString *TVD_EXTENSION = @"tvd";
static NSString *TVF_EXTENSION = @"tvf";

#include "Store/LCDirectory.h"

@class LCIndexOutput;
@class LCFieldInfos;
@class LCTVField; // private

@interface LCTermVectorsWriter: NSObject
{
  LCIndexOutput *tvx, *tvd, *tvf;
  NSMutableArray *fields;
  NSMutableArray *terms;
  LCFieldInfos *fieldInfos;
  LCTVField *currentField;
  long long currentDocPointer;
}
- (id) initWithDirectory: (id <LCDirectory>) directory
                segment: (NSString *) segment
	       fieldInfos: (LCFieldInfos *) fieldInfos;
- (void) openDocument;
- (void) closeDocument;
- (BOOL) isDocumentOpen;
- (void) openField: (NSString *) field;
- (void) closeField;
- (BOOL) isFieldOpen;
- (void) addTerm: (NSString *) termText freq: (long) freq;
- (void) addTerm: (NSString *) termText freq: (long) freq
         positions: (NSArray *) positions offsets: (NSArray *) offsets;
- (void) addAllDocVectors: (NSArray *) vectors;
- (void) close;

@end
  
#endif /* __LUCENE_INDEX_TERM_VECTORS_WRITER__ */
