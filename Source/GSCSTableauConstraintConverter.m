
#import "GSCSTableauConstraintConverter.h"
#import "GSCSVariable+PrivateMethods.h"

@implementation GSCSTableauConstraintConverter

- (instancetype)init
{
    self = [super init];
    if (self) {
        _slackCounter = 0;
        _dummyCounter = 0;
        _variableCounter = 0;
        _constraintAuxiliaryVariables = [NSMapTable weakToStrongObjectsMapTable];
        RETAIN(_constraintAuxiliaryVariables);
    }
    return self;
}

/** Make a new linear expression representing the constraint c,
 ** replacing any basic variables with their defining expressions.
 * Normalize if necessary so that the constant is non-negative.  If
 * the constraint is non-required, give its error variables an
 * appropriate weight in the objective function. */
-(GSCSLinearExpression*)createExpression: (GSCSConstraint *)constraint expressionResult: (ExpressionResult*)expressionResult tableau: (GSCSTableau*)tableau objective: (GSCSVariable*)_objective
{
    GSCSLinearExpression *constraintExpression = [constraint expression];
    
    GSCSLinearExpression *newExpression = [[GSCSLinearExpression alloc] init];
    [newExpression setConstant:[constraintExpression constant]];
    
    for (GSCSVariable *term in constraintExpression.termVariables) {
        CGFloat termCoefficient = [[constraintExpression multiplierForTerm: term] doubleValue];
        GSCSLinearExpression *rowExpression = [tableau rowExpressionForVariable:term];
        if ([tableau isBasicVariable:term]) {
            [tableau addNewExpression:rowExpression toExpression:newExpression n:termCoefficient subject:nil];
        } else {
            [tableau addVariable:term toExpression:newExpression withCoefficient:termCoefficient subject:nil];
        }
    }
    
    ExpressionResult *result = expressionResult;
    result->expression = nil;
    result->minus = nil;
    result->plus = nil;
    result->marker = nil;

    if ([_constraintAuxiliaryVariables objectForKey:constraint] == nil) {
        [_constraintAuxiliaryVariables setObject:[NSMutableDictionary dictionary] forKey:constraint];
    }
    
    if ([constraint isInequality]) {
        [self applyInequityConstraint:constraint newExpression:newExpression tableau:tableau result: &result objective: _objective];
    } else {
        [self applyConstraint:constraint newExpression:newExpression result:&result tableau:tableau _objective:_objective];
    }
    
    // the Constant in the Expression should be non-negative. If necessary
    // normalize the Expression by multiplying by -1
    if (newExpression.constant < 0) {
        [newExpression normalize];
    }
    
    return newExpression;
}

- (void)applyConstraint:(GSCSConstraint *)constraint newExpression:(GSCSLinearExpression *)newExpression result:(ExpressionResult **)result tableau: (GSCSTableau*)tableau _objective: (GSCSVariable*)_objective {
    GSCSLinearExpression *constraintExpression = [constraint expression];
    NSMutableDictionary *constraintAuxiliaryVariables = [_constraintAuxiliaryVariables objectForKey:constraint];

    if ([constraint isRequired]) {
        GSCSVariable *dummyVariable;
        if (constraintAuxiliaryVariables[@"d"] != nil) {
            dummyVariable = constraintAuxiliaryVariables[@"d"];
        } else {
            dummyVariable = [self dummyVariableForConstraint: constraint];
            constraintAuxiliaryVariables[@"d"] = dummyVariable;
        }

        (*result)->plus = dummyVariable;
        (*result)->minus = dummyVariable;
        (*result)->previousConstant = constraintExpression.constant;
        [tableau setVariable:dummyVariable onExpression:newExpression withCoefficient:1];
        (*result)->marker = dummyVariable;
    } else {
        // cn is a non-required equality. Add a positive and a negative error
        // variable, making the resulting constraint
        //       expr = eplus - eminus
        // in other words:
        //       expr - eplus + eminus = 0
        
        _slackCounter++;
        GSCSVariable *eplusVariable = [self slackVariableForConstraint:constraint prefix:@"ep"];
        GSCSVariable *eminusVariable = [self slackVariableForConstraint:constraint prefix:@"em"];
                
        [tableau setVariable:eplusVariable onExpression:newExpression withCoefficient:-1];
        [tableau setVariable:eminusVariable onExpression:newExpression withCoefficient:1];
        
        GSCSLinearExpression *zRow = [tableau rowExpressionForVariable: _objective];
        CGFloat swCoefficient = [constraint.strength strength];
        
        [tableau setVariable:eplusVariable onExpression:zRow withCoefficient:swCoefficient];
        [tableau addMappingFromExpressionVariable:eplusVariable toRowVariable:_objective];
        
        [tableau setVariable:eminusVariable onExpression:zRow withCoefficient:swCoefficient];
        [tableau addMappingFromExpressionVariable:eminusVariable toRowVariable:_objective];
        
        (*result)->marker = eplusVariable;
        (*result)->plus = eplusVariable;
        (*result)->minus = eminusVariable;
        (*result)->previousConstant = constraintExpression.constant;
    }
}

/*
// Add a slack variable. The original constraint
// is expr>=0, so that the resulting equality is expr-slackVar=0. If cn is
// also non-required Add a negative error variable, giving:
//
//    expr - slackVar = -errorVar
//
// in other words:
//
//    expr - slackVar + errorVar = 0
//
// Since both of these variables are newly created we can just Add
// them to the Expression (they can't be basic).
*/
- (void)applyInequityConstraint:(GSCSConstraint *)constraint newExpression:(GSCSLinearExpression *)newExpression tableau: (GSCSTableau*)tableau result:(ExpressionResult **)result objective: (GSCSVariable*)_objective {
  _slackCounter++;
  GSCSVariable *slackVariable = [self createSlackVariableWithPrefix:@"s"];
  [tableau setVariable:slackVariable onExpression:newExpression withCoefficient:-1];
  
  (*result)->marker = slackVariable;
  
  if (![constraint isRequired]) {
      GSCSVariable *eminusSlackVariable = [self createSlackVariableWithPrefix:@"em"];
      [newExpression addVariable:eminusSlackVariable coefficient:1];
      
      CGFloat eminusCoefficient = [constraint.strength strength];
      GSCSLinearExpression *zRow = [tableau rowExpressionForVariable: _objective];
      [tableau setVariable:eminusSlackVariable onExpression:zRow withCoefficient: eminusCoefficient];
      // TODO check this no test hits this code
      (*result)->minus = eminusSlackVariable;
      [tableau addMappingFromExpressionVariable:eminusSlackVariable toRowVariable: _objective];
  }
}

-(GSCSVariable*)slackVariableForConstraint: (GSCSConstraint*)constraint prefix: (NSString*)prefix
{
    NSMutableDictionary *constraintAuxiliaryVariables = [_constraintAuxiliaryVariables objectForKey:constraint];

    if (constraintAuxiliaryVariables[prefix] != nil) {
        return constraintAuxiliaryVariables[prefix];
    } else {
        GSCSVariable *slackVariable = [self createSlackVariableWithPrefix:prefix];
        constraintAuxiliaryVariables[prefix] = slackVariable;
        return slackVariable;
    }
}

-(GSCSVariable*)createSlackVariableWithPrefix: (NSString*)prefix
{
    GSCSVariable *slackVariable = [GSCSVariable slackVariableWithName:[NSString stringWithFormat:@"%@%d", prefix, _slackCounter]];
    // [[GSCSSlackVariable alloc] initWithName:[NSString stringWithFormat:@"%@%d", prefix, _slackCounter]];
    slackVariable.id = [self getNextVariableId];
    _variableCounter++;
    return slackVariable;
}

-(GSCSVariable*)dummyVariableForConstraint: (GSCSConstraint*)constraint
{
    NSMutableDictionary *constraintAuxiliaryVariables = [_constraintAuxiliaryVariables objectForKey:constraint];
    if (constraintAuxiliaryVariables[@"d"] != nil) {
        return constraintAuxiliaryVariables[@"d"];
    }
    
    _dummyCounter++;
    GSCSVariable *dummyVariable = [GSCSVariable dummyVariableWithName:[NSString stringWithFormat:@"d%d", _dummyCounter]];
    constraintAuxiliaryVariables[@"d"] = dummyVariable;
    
    return dummyVariable;
}

-(NSUInteger)getNextVariableId
{
    return ++_variableCounter;
}

-(void)dealloc
{
    RELEASE(_constraintAuxiliaryVariables);
    [super dealloc];
}
@end
