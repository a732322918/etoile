/*
**  CodeParser.m
**
**  Copyright (c) 2003, 2006
**
**  Author: Yen-Ju  <yjchenx gmail>
**
**  This library is free software; you can redistribute it and/or
**  modify it under the terms of the GNU Lesser General Public
**  License as published by the Free Software Foundation, in version 2.1
**  of the License
**
**  This library is distributed in the hope that it will be useful,
**  but WITHOUT ANY WARRANTY; without even the implied warranty of
**  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
**  Lesser General Public License for more details.
**
**  You should have received a copy of the GNU Lesser General Public
**  License along with this library; if not, write to the Free Software
**  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#import "CodeParser.h"
#import "GNUstep.h"

typedef enum _CodeType {
  StringCodeType, /* 41-5A, 61-7A, 5F */
  NumberCodeType, /* 30-39 */
  SpaceAndNewLineCodeType, /* 20, 0a, 0d */
  SymbolCodeType, /* others */
  InvisibleCodeType /* before (contain) 1F, except 0a, 0d */
} CodeType;

@implementation CodeParser

- (CodeParser *) initWithHandler: (id <CodeHandler>) handler
                          string: (NSString *) text
{
  if (handler == nil) return nil;
  if (text == nil) return nil;

  self = [self init];

  ASSIGN(_handler, handler);
  ASSIGN(_string, text);

  _length = [_string length];
  _uchar = malloc(sizeof(unichar)*_length);
  [_string getCharacters: _uchar];

  return self;
}

/* Private function*/
CodeType codeType(unichar *ch)
{
  if ( ((*ch > 0x40) && (*ch < 0x5B)) ||
       ((*ch > 0x60) && (*ch < 0x7B)) ||
       (*ch == 0x5F) )
    {
      return StringCodeType;
    }
  else if ((*ch == 0x20) || (*ch == 0x0a) || (*ch == 0x0d))
    {
      return SpaceAndNewLineCodeType;
    }
  else if ((*ch > 0x2F) && (*ch < 0x3A))
    {
      return NumberCodeType;
    }
  else if (*ch < 0x20)
    {
      return InvisibleCodeType;
    }
  else if ((*ch > 0x20) && (*ch < 0x7F))
    {
      return SymbolCodeType;
    }
  else 
    {
      return StringCodeType;
    } 
}

- (void) parse
{
  unsigned int i, start, end;
  CodeType startType, endType;
  NSString *out;

  start = end = 0;
  startType = codeType(_uchar+start);

  for (i = 1; i < _length+1; i++)
    {
      end = i;
      endType = codeType(_uchar+end);
      
      if ((startType != endType) || (end == _length))
        {
          /* Check period in number */
          if ((startType == NumberCodeType) && (_uchar[end] == 0x2E))
            continue;

          //out = [_string substringWithRange: NSMakeRange(start, end-start)];
          if (startType == StringCodeType)
            {
              out = [_string substringWithRange: NSMakeRange(start, end-start)];
              [_handler string: out];
            }
          else if (startType == NumberCodeType)
            {
              out = [_string substringWithRange: NSMakeRange(start, end-start)];
              [_handler number: out];
            }
          else if (startType == SpaceAndNewLineCodeType)
            {
              unsigned int j, jlen = end-start/*[out length]*/;
              for (j = 0; j < jlen; j++)
                {
                  //[_handler spaceAndNewLine: [out substringWithRange: NSMakeRange(j, 1)]];
                  //(*impSpaceAndNewLine)(_handler, selSpaceAndNewLine, [out substringWithRange: NSMakeRange(j, 1)]);
                  //(*impSpaceAndNewLine)(_handler, selSpaceAndNewLine, _uchar[start+j]);
                  [_handler spaceAndNewLine: _uchar[start+j]];
                  
                }
            }
          else if (startType == SymbolCodeType)
            {
              out = [_string substringWithRange: NSMakeRange(start, end-start)];
              [_handler symbol: out];
            }
          else if (startType == InvisibleCodeType)
            {
              unsigned int j, jlen = end-start/*[out length]*/;
              for (j = 0; j < jlen; j++)
                {
                  //[_handler invisible: out];
                  //(*impInvisible)(_handler, selInvisible, out);
                  //(*impInvisible)(_handler, selInvisible, _uchar[start+j]);
                  [_handler invisible: _uchar[start+j]];
                }
            }
          start = i;
          startType = codeType(_uchar+start);
        }
    }
}


- (id) init
{
  self = [super init];
  return self;
}

- (void) dealloc
{
  free(_uchar);
  RELEASE(_handler);
  RELEASE(_string);
  [super dealloc];
}

@end
