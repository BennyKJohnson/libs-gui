#import "GSCSSimplexSolver.h"
#import "GSCSFloatComparator.h"
#import "GSCSVariable.h"
#import "GSCSEditInfo.h"
#import "GSCSVariable+PrivateMethods.h"
#import "GSCSSolution.h"

NSString * const GSCSErrorDomain = @"com.cassowary";

@implementation GSCSSimplexSolver

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tableau = [[GSCSTableau alloc] init];

        _stayMinusErrorVariables = [NSMutableArray array];
        RETAIN(_stayMinusErrorVariables);

        _stayPlusErrorVariables = [NSMutableArray array];
        RETAIN(_stayPlusErrorVariables);
  
        _markerVariablesByConstraints = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
        valueOptions:NSMapTableStrongMemory];
        RETAIN(_markerVariablesByConstraints);

        _constraintsByMarkerVariables = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
                                                              valueOptions:NSMapTableStrongMemory];
        RETAIN(_constraintsByMarkerVariables);

        _errorVariables = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
        valueOptions:NSMapTableStrongMemory];
        RETAIN(_errorVariables);
                
        _artificialCounter = 0;
        
        _constraintConverter = [[GSCSTableauConstraintConverter alloc] init];
        
        _addedConstraints = [NSMutableArray array];
        RETAIN(_addedConstraints);
                
        self.editVariableManager = [[GSCSEditVariableManager alloc] init];

        _needsSolving = NO;
    }
    
    return self;
}

-(void)addConstraints: (NSArray*)constraints
{
    for (GSCSConstraint *constraint in constraints) {
        [self _addConstraint:constraint tableau:_tableau entryVariable:nil];
        [_addedConstraints addObject: constraint];
    }
    
    if (self.autoSolve) {
        [self solve];
    }
}

-(void)addConstraint:(GSCSConstraint *)constraint
{
    [self _addConstraint:constraint tableau:_tableau entryVariable:nil];
    
    [_addedConstraints addObject: constraint];
    if (self.autoSolve) {
        [self solve];
    }
}

-(void)_addConstraint: (GSCSConstraint*)constraint tableau: (GSCSTableau*)tableau entryVariable: (GSCSVariable*)entryVariable
{
    if ([constraint isEditConstraint] && ![[constraint variable] isExternal]) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Cannot have an edit variable with a non external variable" userInfo:nil] raise];
    }
    
    ExpressionResult expressionResult;
    
    GSCSLinearExpression *expression = [_constraintConverter createExpression:constraint expressionResult:&expressionResult tableau:tableau objective: _tableau.objective];
    
    [_markerVariablesByConstraints setObject:expressionResult.marker forKey:constraint];
    [_constraintsByMarkerVariables setObject:constraint forKey:expressionResult.marker];

    if ([constraint isStayConstraint]) {
        if (expressionResult.plus != nil) {
            [_stayPlusErrorVariables addObject:expressionResult.plus];
        }
        if (expressionResult.minus != nil) {
            [_stayMinusErrorVariables addObject:expressionResult.minus];
        }
    }
    
    if (![constraint isInequality] && ![constraint isRequired]) {
        [self insertErrorVariable:constraint variable:expressionResult.minus];
        [self insertErrorVariable:constraint variable:expressionResult.plus];
    }
    if ([constraint isInequality] && ![constraint isRequired]) {
        [self insertErrorVariable:constraint variable:expressionResult.minus];
    }
    
    
    BOOL addedDirectly = [self tryAddingExpressionDirectly: expression tableau:tableau];
    if (!addedDirectly) {
        NSError *error = nil;
        [self addWithArtificialVariable:expression error:&error tableau:tableau entryVariable: entryVariable];
        if (error != nil) {
            [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Conflicting constraint" userInfo:nil] raise];
        }
    }
    
    if ([constraint isEditConstraint]) {
        GSCSEditInfo *editInfo = [[GSCSEditInfo alloc] initWithVariable:constraint.variable constraint:constraint plusVariable: expressionResult.plus minusVariable:expressionResult.minus previousConstant:expressionResult.previousConstant];
        [self.editVariableManager addEditInfo:editInfo];
    }
    
    _needsSolving = YES;
}

-(BOOL)tryAddingExpressionDirectly: (GSCSLinearExpression*)expression tableau: (GSCSTableau*)tableau {
    GSCSVariable *subject = [self choseSubject:expression tableau:tableau];
    if (subject == nil) {
        return NO;
    }

    [expression newSubject: subject];
    if ([tableau hasColumnForVariable: subject]) {
        [tableau substituteOutVariable:subject forExpression:expression];
    }
    
    [tableau addRowForVariable:subject equalsExpression:expression];
    return YES;
}

-(void)removeConstraints: (NSArray*)constraints
{
    for (GSCSConstraint *constraint in constraints) {
        [self removeConstraint:constraint];
    }
    if (self.autoSolve) {
        [self solve];
    }
}

-(void)removeConstraint: (GSCSConstraint*)constraint
{
    [self _removeConstraint:constraint tableau:_tableau];
    // Do additional housekeeping for edit/stay constraints
    if ([constraint isEditConstraint]) {
        GSCSEditInfo *editInfoForConstraint = [self.editVariableManager editInfoForConstraint:constraint];
        [_tableau removeColumn:editInfoForConstraint.minusVariable];
        [self.editVariableManager removeEditInfoForConstraint:constraint];
    } else if ([constraint isStayConstraint] && [_errorVariables objectForKey:constraint] != nil) {
        [self removeStayErrorVariablesForConstraint:constraint];
    }
    [_addedConstraints removeObject:constraint];
    
    if (self.autoSolve) {
        [self solve];
    }
}

-(void)_removeConstraint: (GSCSConstraint*)constraint tableau: (GSCSTableau*)tableau
{
    [self resetStayConstraints];
    
    GSCSLinearExpression *zRow = [tableau rowExpressionForVariable:_tableau.objective];
    NSArray *constraintErrorVars = [_errorVariables objectForKey:constraint];
    if (constraintErrorVars != nil) {
        for (GSCSVariable *errorVariable in constraintErrorVars) {
            CGFloat value = -[constraint.strength strength];

            if ([tableau isBasicVariable:errorVariable]) {
                GSCSLinearExpression *errorVariableRowExpression = [tableau rowExpressionForVariable:errorVariable];
                [tableau addNewExpression:errorVariableRowExpression toExpression:zRow n:value subject:_tableau.objective];
            } else {
                [tableau addVariable:errorVariable toExpression:zRow withCoefficient:value subject: _tableau.objective];
            }
        }
    }

    GSCSVariable *constraintMarkerVariable = [_markerVariablesByConstraints objectForKey:constraint];
    if (constraintMarkerVariable == nil) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"Marker variable not found for constraint" userInfo:nil] raise];
    }
    [_markerVariablesByConstraints removeObjectForKey:constraint];
    [_constraintsByMarkerVariables removeObjectForKey:constraintMarkerVariable];
    
    if ([tableau rowExpressionForVariable:constraintMarkerVariable] == nil) {
        GSCSVariable * exitVariable = [self resolveExitVariableRemoveConstraint:constraintMarkerVariable];
        if (exitVariable) {
            [tableau pivotWithEntryVariable:constraintMarkerVariable exitVariable:exitVariable];
        } else {
            // ExitVar doesn't occur in any equations, so just remove it.
            [tableau removeColumn:constraintMarkerVariable];
        }
    }
    
    if ([tableau isBasicVariable:constraintMarkerVariable]) {
        [tableau removeRowForVariable:constraintMarkerVariable];
    }
    
    // Delete any error variables.  If cn is an inequality, it also
    // contains a slack variable; but we use that as the marker variable
    // and so it has been deleted when we removed its row.
    for (GSCSVariable *errorVariable in constraintErrorVars) {
        if (errorVariable != constraintMarkerVariable) {
            [tableau removeColumn: errorVariable];
        }
    }
    
    if (constraintErrorVars != nil) {
        [_errorVariables removeObjectForKey: constraint];
    }
    
    _needsSolving = YES;
}

- (GSCSVariable *)resolveExitVariableRemoveConstraint:(GSCSVariable *)constraintMarkerVariable {
    
    GSCSVariable *exitVariable = [self findExitVariableForMarkerVariableThatIsRestrictedAndHasANegativeCoefficient:constraintMarkerVariable];
    if (exitVariable != nil) {
        return exitVariable;
    }
    
    // If we didn't set exitvar above, then either the marker
      // variable has a positive coefficient in all equations, or it
      // only occurs in equations for unrestricted variables.  If it
      // does occur in an equation for a restricted variable, pick the
      // equation that gives the smallest ratio.  (The row with the
      // marker variable will become infeasible, but all the other rows
      // will still be feasible; and we will be dropping the row with
      // the marker variable.  In effect we are removing the
      // non-negativity restriction on the marker variable.)
    if (exitVariable == nil) {
        exitVariable = [_tableau findExitVariableForEquationWhichMinimizesRatioOfRestrictedVariables: constraintMarkerVariable];
    }
    
    if (exitVariable == nil) {
        // Pick an exit var from among the unrestricted variables whose equation involves the marker var
        NSSet *column = [_tableau columnForVariable:constraintMarkerVariable];
        for (GSCSVariable *variable in column) {
            if (variable != _tableau.objective) {
                exitVariable = variable;
                break;
            }
        }
    }
    return exitVariable;
}

- (GSCSVariable*)findExitVariableForMarkerVariableThatIsRestrictedAndHasANegativeCoefficient:(GSCSVariable *)constraintMarkerVariable {
    GSCSVariable *exitVariable = nil;
    CGFloat minRatio = 0;
    
    NSSet *column = [_tableau columnForVariable:constraintMarkerVariable];
    for (GSCSVariable *variable in column) {
        if ([variable isRestricted]) {
            GSCSLinearExpression *expression = [_tableau rowExpressionForVariable:variable];
            CGFloat coefficient = [expression coefficientForTerm:constraintMarkerVariable];
            if (coefficient < 0) {
                CGFloat r = -expression.constant / coefficient;
                BOOL isNewExitVarCandidate = exitVariable == nil || r < minRatio || ([GSCSFloatComparator isApproxiatelyEqual:r b:minRatio] && [self shouldPreferPivotableVariable:variable overPivotableVariable:exitVariable]);
                if (isNewExitVarCandidate) {
                    minRatio = r;
                    exitVariable = variable;
                }
            }
        }
    }
    
    return exitVariable;
}

- (void)removeStayErrorVariablesForConstraint:(GSCSConstraint *)constraint {
    NSArray *constraintErrorVars = [_errorVariables objectForKey:constraint];
    for (GSCSVariable *variable in [_stayPlusErrorVariables copy]) {
        if ([constraintErrorVars containsObject:variable]) {
            [_stayPlusErrorVariables removeObject:variable];
        }
    }
    for (GSCSVariable *variable in [_stayMinusErrorVariables copy]) {
        if ([constraintErrorVars containsObject:variable]) {
            [_stayPlusErrorVariables removeObject:variable];
        }
    }
}

-(GSCSVariable*)choseSubject: (GSCSLinearExpression*)expression tableau: (GSCSTableau*)tableau
{
    GSCSVariable *subject = [self chooseSubjectFromExpression:expression tableau:tableau];
    if (subject != nil) {
        return subject;
    }
    
    if (![expression containsOnlyDummyVariables]) {
        return nil;
    }
    
    // variables, then we can pick a dummy variable as the subject.
    float coefficent = 0;
    for (GSCSVariable *term in expression.termVariables) {
         if (![tableau hasColumnForVariable:term]) {
            subject = term;
            coefficent = [expression coefficientForTerm:term];
        }
    }
    
    // If we get this far, all of the variables in the expression should
     // be dummy variables.  If the constant is nonzero we are trying to
     // add an unsatisfiable required constraint.  (Remember that dummy
     // variables must take on a value of 0.)
    if (![GSCSFloatComparator isApproxiatelyZero: expression.constant] ) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Unsatisfiable required constraint" userInfo:nil] raise];
    }
    
    // Otherwise, if the constant is grater than zero, multiply by -1 if necessary to
    // make the coefficient for the subject negative.
    if (coefficent > 0) {
        [expression setConstant:expression.constant * -1];
    }
    
    return subject;
}

- (GSCSVariable * _Nonnull)chooseSubjectFromExpression:(GSCSLinearExpression * _Nonnull)expression tableau: (GSCSTableau*)tableau {
    BOOL foundUnrestricted = NO;
    BOOL foundNewRestricted = NO;
    
    GSCSVariable *subject = nil;
    for (GSCSVariable *variable in expression.termVariables) {
        CGFloat coefficent = [[expression multiplierForTerm:variable] floatValue];
        BOOL isNewVariable = ![tableau hasColumnForVariable:variable];
        
        if (foundUnrestricted && ![variable isRestricted] && isNewVariable) {
            return variable;
        } else if (foundUnrestricted == NO) {
            if ([variable isRestricted]) {
                if (!foundNewRestricted && ![variable isDummy] && coefficent < 0) {
                    NSSet *col = [tableau columnForVariable:variable];
                    if (col == nil || ([col count] == 1 && [tableau hasColumnForVariable:_tableau.objective])) {
                        subject = variable;
                        foundNewRestricted = true;
                    }
                }
            } else {
                subject = variable;
                foundUnrestricted = YES;
            }
        }
    }
    
    return subject;
}

-(void)beginEdit
{
    if ([self.editVariableManager isEmpty]) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"No edit variables have been added to solver" userInfo:nil] raise];
    }
    [_tableau.infeasibleRows removeAllObjects];
    [self resetStayConstraints];
    [self.editVariableManager pushEditVariableCount];
}

-(void)endEdit
{
    if ([self.editVariableManager isEmpty]) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"No edit variables have been added to solver" userInfo:nil] raise];
    }
    
    [self resolve];
    
    for (GSCSEditInfo *editInfo in [self.editVariableManager getNextSet]) {
        [self removeEditVariableForEditInfo: editInfo];
    }
}

-(void)resolve
{
    [self dualOptimize];
    [_tableau.infeasibleRows removeAllObjects];
    _needsSolving = false;
    [self resetStayConstraints];
}

-(void)removeEditVariableForEditInfo: (GSCSEditInfo*)editInfoForVariable
{
    if (editInfoForVariable == nil) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to find edit info for variable" userInfo:nil] raise];
    }
    
    [self _removeConstraint:editInfoForVariable.constraint tableau: _tableau];
    [_tableau removeColumn:editInfoForVariable.minusVariable];
    [self.editVariableManager removeEditInfo:editInfoForVariable];
}

-(void)suggestEditVariables: (NSArray*)suggestions
{
    for (GSCSSuggestion *suggestion in suggestions) {
        [self addEditVariableForVariable:[suggestion variable] strength:[GSCSStrength strengthStrong]];
    }
    
    [self beginEdit];
    for (GSCSSuggestion *suggestion in suggestions) {
        [self suggestEditVariable:[suggestion variable] equals:[suggestion value]];
    }
    [self endEdit];
}


-(void)suggestVariable: (GSCSVariable*)varible equals: (CGFloat)value
{
    [self addEditVariableForVariable:varible strength:[GSCSStrength strengthStrong]];
    [self beginEdit];
    [self suggestEditVariable:varible equals:value];
    [self endEdit];
}

-(void)suggestEditConstraint: (GSCSConstraint*)constraint equals: (CGFloat)value
{
    if (![constraint isEditConstraint]) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Not an edit constraint" userInfo:nil] raise];
    }
    
    GSCSEditInfo *editInfo = [self.editVariableManager editInfoForConstraint:constraint];
    if (editInfo == nil) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Edit Info not found for constraint" userInfo:nil] raise];
    }
    
    CGFloat delta = value - editInfo.previousConstant;
    editInfo.previousConstant = delta;
    [self deltaEditConstant:delta plusErrorVariable:editInfo.plusVariable minusErrorVariable:editInfo.minusVariable];
}

-(void)suggestEditVariable: (GSCSVariable*)variable equals: (CGFloat)value
{
    for (GSCSEditInfo *editInfo in [self.editVariableManager editInfosForVariable:variable]) {
        CGFloat delta = value - editInfo.previousConstant;
        editInfo.previousConstant = value;
        [self deltaEditConstant:delta plusErrorVariable:editInfo.plusVariable minusErrorVariable:editInfo.minusVariable];
    }
}

-(void)deltaEditConstant: (CGFloat)delta plusErrorVariable: (GSCSVariable*)plusErrorVariable minusErrorVariable: (GSCSVariable*)minusErrorVariable
{
    GSCSLinearExpression *plusExpression = [_tableau rowExpressionForVariable:plusErrorVariable];
    if (plusExpression != nil) {
        plusExpression.constant += delta;
        if (plusExpression.constant < 0) {
            [_tableau.infeasibleRows addObject:plusErrorVariable];
        }
        return;
    }
    
    GSCSLinearExpression *minusExpression = [_tableau rowExpressionForVariable:minusErrorVariable];
    if (minusExpression != nil) {
        minusExpression.constant += -delta;
        if (minusExpression.constant < 0) {
            [_tableau.infeasibleRows addObject:minusErrorVariable];
        }
        return;
    }
    
    // Neither is basic.  So they must both be nonbasic, and will both
    // occur in exactly the same expressions.  Find all the expressions
    // in which they occur by finding the column for the minusErrorVar
    // (it doesn't matter whether we look for that one or for
    // plusErrorVar).  Fix the constants in these expressions.
    
    NSSet *columnVars = [_tableau columnForVariable:minusErrorVariable];
    if (!columnVars) {
        NSLog(@"columns for variable is null");
    }
    
    for (GSCSVariable *basicVariable in columnVars) {
        GSCSLinearExpression *expression = [_tableau rowExpressionForVariable: basicVariable];
        CGFloat coefficient = [expression coefficientForTerm:minusErrorVariable];
        expression.constant += coefficient * delta;

        if (basicVariable.isRestricted && expression.constant < 0) {
            [_tableau.infeasibleRows addObject:basicVariable];
        }
    }
}


-(void)addEditVariableForVariable: (GSCSVariable*)variable strength: (GSCSStrength*)strength
{
    GSCSLinearExpression *variableExpression = [_tableau rowExpressionForVariable:variable];
    if (variableExpression) {
        variable.value = variableExpression.constant;
    }
    
    GSCSConstraint *editVariableConstraint = [[GSCSConstraint alloc] initEditConstraintWithVariable:variable strength:strength];
    [self addConstraint: editVariableConstraint];
}

-(void)addWithArtificialVariable: (GSCSLinearExpression*)expression error: (NSError **)error tableau: (GSCSTableau*)tableau entryVariable: (GSCSVariable*)entryVariable
{
    
    // The artificial objective is av, which we know is equal to expr
    // (which contains only parametric variables).
    GSCSVariable *artificialVariable = [GSCSVariable slackVariableWithName:[NSString stringWithFormat:@"%@%d", @"a", ++_artificialCounter]];
    
    GSCSVariable *artificialZ = [GSCSVariable objectiveVariableWithName:@"az"];
    GSCSLinearExpression *row = [expression copy];
    
    // Objective is treated as a row in the tableau,
    // so do the substitution for its value (we are minimizing
    // the artificial variable).
    // This row will be removed from the tableau after optimizing.
    [tableau addRowForVariable:artificialZ equalsExpression:row];
    
    // Add the normal row to the tableau -- when artifical
    // variable is minimized to 0 (if possible)
    // this row remains in the tableau to maintain the constraint
    // we are trying to add.
    [tableau addRowForVariable: artificialVariable equalsExpression:expression];

    
    // Try to optimize az to 0.
    // Note we are *not* optimizing the real objective, but optimizing
    // the artificial objective to see if the error in the constraint
    // we are adding can be set to 0.
    [self optimize: artificialZ tableau:tableau entryVariable: entryVariable];
    
    GSCSLinearExpression *azTableauRow = [tableau rowExpressionForVariable:artificialZ];
    
    if (![GSCSFloatComparator isApproxiatelyZero:azTableauRow.constant]) {
        [tableau removeRowForVariable:artificialZ];
        [tableau removeColumn:artificialVariable];
        *error = [[NSError alloc] initWithDomain:GSCSErrorDomain code:GSCSErrorCodeRequired userInfo:nil];
        return;
    }
    
    GSCSLinearExpression *rowExpression = [tableau rowExpressionForVariable: artificialVariable];
    if (rowExpression != nil) {
        if ([rowExpression isConstant]) {
            [tableau removeRowForVariable:artificialVariable];
            [tableau removeRowForVariable:artificialZ];
            return;
        }
        GSCSVariable *entryVariable = [rowExpression anyPivotableVariable];
        [tableau pivotWithEntryVariable:entryVariable exitVariable:artificialVariable];
    }
    
    [tableau removeColumn:artificialVariable];
    [tableau removeRowForVariable:artificialZ];
}

-(GSCSSolution*)solve
{
    [self optimize:_tableau.objective tableau:_tableau entryVariable:nil];
    _needsSolving = false;
    return [self solutionFromTableau: _tableau];
}

-(NSArray*)solveAll
{
    GSCSSolution *solution = [self solve];

    NSArray *specialVariables = [_tableau substitedOutNonBasicPivotableVariables: _tableau.objective];
    if ([specialVariables count] == 0) {
        return [NSArray arrayWithObject:solution];
    }
    
    // TODO handle edit and stay constraints
    NSMutableArray *solutions = [NSMutableArray arrayWithObject:solution];
    for (GSCSVariable *specialVariable in specialVariables) {
        GSCSTableau * tableau = [[GSCSTableau alloc] init];
        
        for (GSCSConstraint *constraint in _addedConstraints) {
            [self _addConstraint:constraint tableau:tableau entryVariable:specialVariable];
        }
        
        [solutions addObject: [self solutionFromTableau:tableau]];
    }
    
    return solutions;
}

-(GSCSSolution*)solutionFromTableau: (GSCSTableau*)tableau
{
    GSCSSolution *solution = [[GSCSSolution alloc] init];
    for (GSCSVariable *variable in tableau.externalRows) {
        CGFloat calculatedValue = [tableau rowExpressionForVariable:variable].constant;
        [solution setResult:calculatedValue forVariable: variable];
    }
        
    return solution;
}

// Minimize the value of the objective.  (The tableau should already be feasible.)
-(void)optimize: (GSCSVariable*)zVariable tableau: (GSCSTableau*)tableau entryVariable: (GSCSVariable*)preferredEntryVariable
{
    GSCSLinearExpression *zRow = [tableau rowExpressionForVariable:zVariable];
    if (zRow == nil) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"Optimize zRow is null" userInfo:nil] raise];
    }
        
    // Find the most negative coefficient in the objective function (ignoring
    // the non-pivotable dummy variables). If all coefficients are positive
    // we're done
    NSArray *entryVariableCandidates = [zRow findPivotableVariablesWithMostNegativeCoefficient];
    GSCSVariable *entryVariable = nil;
    if ([entryVariableCandidates count] > 0) {
        entryVariable = entryVariableCandidates[0];
        if (preferredEntryVariable && [entryVariableCandidates containsObject:preferredEntryVariable]) {
            entryVariable = preferredEntryVariable;
        }
    }
    
    CGFloat objectiveCoefficient = entryVariable != nil ? [zRow coefficientForTerm:entryVariable] : 0;
    while (objectiveCoefficient < -GSCSEpsilon) {
        // choose which variable to move out of the basis
        // Only consider pivotable basic variables
        // (i.e. restricted, non-dummy variables)
        GSCSVariable *exitVariable = [tableau findPivotableExitVariable:entryVariable];
        if (exitVariable == nil) {
            [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"Objective function is unbounded in optimize" userInfo:nil] raise];
        }
        [tableau pivotWithEntryVariable:entryVariable exitVariable:exitVariable];
        
        objectiveCoefficient = 0;
        
        NSArray *entryVariableCandidatesB = [zRow findPivotableVariablesWithMostNegativeCoefficient];
        if ([entryVariableCandidatesB count] > 0) {
            entryVariable = entryVariableCandidatesB[0];
        }
        if (entryVariable != nil) {
            objectiveCoefficient = [zRow coefficientForTerm:entryVariable];
        }
    }
}

-(BOOL)shouldPreferPivotableVariable: (GSCSVariable*)lhs overPivotableVariable: (GSCSVariable*)rhs
{
    return [lhs id] < [rhs id];
}

// We have set new values for the constants in the edit constraints.
// Re-Optimize using the dual simplex algorithm.
-(void)dualOptimize
{
    while ([_tableau hasInfeasibleRows]) {
        GSCSVariable *exitVariable = [_tableau.infeasibleRows firstObject];
        [_tableau.infeasibleRows removeObject:exitVariable];
        
        GSCSLinearExpression *exitVariableExpression = [_tableau rowExpressionForVariable:exitVariable];
        if (!exitVariableExpression) {
              continue;
        }
        // exitVar might have become basic after some other pivoting
        // so allow for the case of its not being there any longer
        if (exitVariableExpression.constant < 0)
        {
            GSCSVariable *entryVariable = [self resolveDualOptimizePivotEntryVariableForExpression: exitVariableExpression];
            [_tableau pivotWithEntryVariable:entryVariable exitVariable:exitVariable];
        }
        
    }
}

- (GSCSVariable*)resolveDualOptimizePivotEntryVariableForExpression:(GSCSLinearExpression *)expression {
    CGFloat ratio = DBL_MAX;
    GSCSLinearExpression *zRow = [_tableau rowExpressionForVariable: _tableau.objective];
    GSCSVariable *entryVariable = nil;

    // Order of expression variables has an effect on the pivot and also when slack variables were created
    for (GSCSVariable *term in expression.termVariables) {
        CGFloat coefficient = [expression coefficientForTerm:term];
        if (coefficient > 0 && [term isPivotable]) {
            CGFloat zCoefficient = [zRow coefficientForTerm:term];
            CGFloat r = zCoefficient / coefficient;
            
            if (r < ratio || ([GSCSFloatComparator isApproxiatelyEqual:r b:ratio] && [self shouldPreferPivotableVariable:term overPivotableVariable:entryVariable])) {
                entryVariable = term;
                ratio = r;
            }
        }
    }
    if (ratio == DBL_MAX) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"ratio == nil (MAX_VALUE) in dualOptimize" userInfo:nil] raise];
    }
    return entryVariable;
}

-(void)insertErrorVariable: (GSCSConstraint*)constraint variable: (GSCSVariable*)variable
{
    NSMutableSet *constraintSet = [_errorVariables objectForKey:constraint];
    if (constraintSet == nil) {
        constraintSet = [NSMutableSet set];
        [_errorVariables setObject:constraintSet forKey:constraint];
    }
    [constraintSet addObject:variable];
}

-(void)resetStayConstraints
{
    if (_stayPlusErrorVariables.count != _stayMinusErrorVariables.count) {
        [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected the number of stayPlusErrorVariables to match the number of stayMinusErrorVariables" userInfo:nil];
    }
    
    for (int i = 0; i < [_stayPlusErrorVariables count]; i++) {
        GSCSVariable *stayPlusErrorVariable = [_stayPlusErrorVariables objectAtIndex:i];
        GSCSVariable *stayMinusErrorVariable = [_stayMinusErrorVariables objectAtIndex:i];
        if ([_tableau isBasicVariable:stayPlusErrorVariable]) {
            GSCSLinearExpression *stayPlusErrorExpression = [_tableau rowExpressionForVariable:stayPlusErrorVariable];
            [stayPlusErrorExpression setConstant:0];
        }
        if ([_tableau isBasicVariable:stayMinusErrorVariable]) {
            GSCSLinearExpression *stayMinusErrorExpression = [_tableau rowExpressionForVariable:stayMinusErrorVariable];
            [stayMinusErrorExpression setConstant:0];
        }
    }
}

-(void)updateConstraint: (GSCSConstraint*)constraint strength: (GSCSStrength*)strength;
{
    NSArray *errorVariablesForConstraint = [_errorVariables objectForKey:constraint];
    if (errorVariablesForConstraint == nil) {
        return;
    }
    
    CGFloat existingCoefficient = [constraint.strength strength];
    [constraint setStrength:strength];
    
    CGFloat newCoefficient = [constraint.strength strength];
    
    if (newCoefficient == existingCoefficient) {
        return;
    }
    
    [self updateErrorVariablesForConstraint:constraint existingCoefficient:existingCoefficient newCoefficient:newCoefficient];

    _needsSolving = true;
    if (self.autoSolve) {
        [self solve];
    }
}

- (void)updateErrorVariablesForConstraint:(GSCSConstraint *)constraint existingCoefficient:(CGFloat)existingCoefficient newCoefficient:(CGFloat)newCoefficient {
    GSCSLinearExpression *objectiveRowExpression = [_tableau rowExpressionForVariable: _tableau.objective];

    NSArray *errorVariablesForConstraint = [_errorVariables objectForKey:constraint];
    for (GSCSVariable *variable in errorVariablesForConstraint) {
        if (![_tableau isBasicVariable:variable]) {
            [_tableau addVariable:variable toExpression:objectiveRowExpression withCoefficient:-existingCoefficient subject:_tableau.objective];
            [_tableau addVariable:variable toExpression:objectiveRowExpression withCoefficient:newCoefficient subject:_tableau.objective];
        } else {
            GSCSLinearExpression *expression = [[_tableau rowExpressionForVariable:variable] copy];
            [_tableau addNewExpression:expression toExpression:objectiveRowExpression n:-existingCoefficient subject:_tableau.objective];
            [_tableau addNewExpression:expression toExpression:objectiveRowExpression n:newCoefficient subject:_tableau.objective];
        }
    }
}

-(BOOL)containsConstraint: (GSCSConstraint*)constraint
{
    return [_markerVariablesByConstraints objectForKey:constraint] != nil;
}

-(BOOL)isValid
{
    return
        [_tableau containsExternalRowForEachExternalRowVariable] &&
        [_tableau containsExternalParametricVariableForEveryExternalTerm];
}

- (void)removeEditVariable: (GSCSVariable*)variable
{
    NSArray *editInfos = [self.editVariableManager editInfosForVariable:variable];
    if (editInfos.count == 0) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Edit variable not found" userInfo:nil] raise];
    }
    
    [self removeConstraint:[[editInfos firstObject] constraint]];
}

-(BOOL)isMultipleSolutions
{
    // First find an optimal solution for the tableau
    [self solve];
    
    // When a non basic pivotable variable (has a zero) in the objective row, this is a sign there are multiple solutions
    return [[_tableau substitedOutNonBasicPivotableVariables: _tableau.objective] count] > 0;
}

-(BOOL)isVariableAmbiguous: (GSCSVariable*)variable
{
    GSCSSolution *defaultOptimalSolution = [self solve];
        
    // Choose a non basic variable to pivot on
    GSCSVariable *entryVariable = [_tableau findNonBasicVariables];
    if (entryVariable == nil) {
        return NO;
    }
    GSCSVariable *exitVariable = [_tableau findPivotableExitVariableWithoutCheck:entryVariable];
    [_tableau pivotWithEntryVariable:entryVariable exitVariable:exitVariable];

    GSCSSolution *s2 = [self solve];
    BOOL variableIsAmbigous = ![GSCSFloatComparator isApproxiatelyEqual: [[defaultOptimalSolution resultForVariable:variable] floatValue] b: [[s2 resultForVariable:variable] floatValue]];
    
    // Revert tableau back to its default solution so future solve calls have the same result
    [self optimizeTableauToSolution: defaultOptimalSolution];
    
    return variableIsAmbigous;
}

-(void)optimizeTableauToSolution: (GSCSSolution*)solution
{
    GSCSSolution *current = [self solve];
    if ([current isEqualToCassowarySolverSolution:solution]) {
        return;
    }
    
    for (GSCSVariable *variable in [solution variables]) {
        if (![GSCSFloatComparator isApproxiatelyEqual:[[current resultForVariable:variable] floatValue] b:[[solution resultForVariable:variable] floatValue]]) {
            GSCSVariable *exitVariable = [_tableau findPivotableExitVariableWithoutCheck:variable];

            [_tableau pivotWithEntryVariable:variable exitVariable:exitVariable];
            
            GSCSSolution *updatedSolution = [self solve];
            if ([updatedSolution isEqualToCassowarySolverSolution:solution]) {
                return;
            }
        }
    }
}

-(NSArray*)constraintsAffectingVariable: (GSCSVariable*)variable
{
    NSMutableArray *constraints = [NSMutableArray array];
    GSCSLinearExpression *rowExpression = [_tableau rowExpressionForVariable:variable];

    for (GSCSVariable *variable in [rowExpression termVariables]) {
        BOOL isNonZeroTerm = ![GSCSFloatComparator isApproxiatelyZero:[rowExpression coefficientForTerm: variable]];
        if (isNonZeroTerm && [_constraintsByMarkerVariables objectForKey:variable] != nil) {
            [constraints addObject:[_constraintsByMarkerVariables objectForKey:variable]];
        }
    }
    
    return constraints;
}

-(void)dealloc
{
    RELEASE(_tableau);
    RELEASE(_stayMinusErrorVariables);
    RELEASE(_stayPlusErrorVariables);
    RELEASE(_markerVariablesByConstraints);
    RELEASE(_constraintsByMarkerVariables);
    RELEASE(_errorVariables);
    RELEASE(_constraintConverter);
    RELEASE(_addedConstraints);
    RELEASE(self.editVariableManager);
    
    [super dealloc];
}

@end
