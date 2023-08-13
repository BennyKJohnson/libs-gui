
#import <Foundation/Foundation.h>
#import "GSCSConstraint.h"
#import "GSCSVariable.h"
#import "GSCSTableau.h"

struct ExpressionResult {
    GSCSLinearExpression *expression;
    GSCSVariable *minus;
    GSCSVariable *plus;
    GSCSVariable *marker;
    double previousConstant;
};
typedef struct ExpressionResult ExpressionResult;

@interface GSCSTableauConstraintConverter : NSObject
{
    int _slackCounter;
    int _dummyCounter;
    int _variableCounter;
    NSMapTable* _constraintAuxiliaryVariables;
}

-(GSCSLinearExpression*)createExpression: (GSCSConstraint *)constraint expressionResult: (ExpressionResult*)expressionResult tableau: (GSCSTableau*)tableau objective: (GSCSVariable*)_objective;

@end
