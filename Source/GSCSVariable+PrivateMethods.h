#import "GSCSVariable.h"

#ifndef _GS_CS_VARIABLE_PRIVATE_METHODS_H
#define _GS_CS_VARIABLE_PRIVATE_METHODS_H

@interface GSCSVariable (PrivateMethods)

+(instancetype)dummyVariableWithName: (NSString*)name;

+(instancetype)slackVariableWithName: (NSString*)name;

+(instancetype)objectiveVariableWithName: (NSString*)name;

@end

#endif
