/* Copyright (C) 2023 Free Software Foundation, Inc.
   
   By: Benjamin Johnson
   Date: 28-2-2023
   This file is part of the GNUstep Library.
   
   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110 USA.
*/

#import <Foundation/Foundation.h>
#import "GSCSTableau.h"
#import "GSCSConstraint.h"
#import "GSCSEditVariableManager.h"
#import "GSCSSuggestion.h"
#import "GSCSTableauConstraintConverter.h"
#import "GSCSSolution.h"

#ifndef _GS_CS_SIMPLEX_SOLVER_H
#define _GS_CS_SIMPLEX_SOLVER_H

extern NSString *const GSCSErrorDomain;

enum GSCSErrorCode {
    GSCSErrorCodeRequired = 1
};

@interface GSCSSimplexSolver : NSObject
{
    int _artificialCounter;
    
    NSMapTable *_markerVariablesByConstraints;
    
    NSMapTable *_constraintsByMarkerVariables;
    
    NSMapTable *_errorVariables;
    
    NSMutableArray *_stayMinusErrorVariables;
    
    NSMutableArray *_stayPlusErrorVariables;
    
    NSMutableArray *_addedConstraints;
    
    BOOL _needsSolving;
    
    GSCSTableau *_tableau;
    
    GSCSTableauConstraintConverter *_constraintConverter;
}

@property BOOL autoSolve;

@property (nonatomic, strong) GSCSEditVariableManager *editVariableManager;

-(void)addConstraint: (GSCSConstraint*)constraint;

-(void)addConstraints: (NSArray*)constraints;

-(void)removeConstraint: (GSCSConstraint*)constraint;

-(void)removeConstraints: (NSArray*)constraints;

-(void)suggestVariable: (GSCSVariable*)varible equals: (CGFloat)value;

-(void)suggestEditVariable: (GSCSVariable*)variable equals: (CGFloat)value;

-(void)suggestEditVariables: (NSArray*)suggestions;

-(void)suggestEditConstraint: (GSCSConstraint*)constraint equals: (CGFloat)value;

- (void)removeEditVariable: (GSCSVariable*)variable;

-(void)beginEdit;

-(void)endEdit;

-(GSCSSolution*)solve;

// If the solver is underconstrained, this method will return the primary solution and alternative solutions
-(NSArray*)solveAll;

-(BOOL)isValid;

-(void)updateConstraint: (GSCSConstraint*)constraint strength: (GSCSStrength*)strength;

-(BOOL)containsConstraint: (GSCSConstraint*)constraint;

-(BOOL)isMultipleSolutions;

-(BOOL)isVariableAmbiguous: (GSCSVariable*)variable;

-(NSArray*)constraintsAffectingVariable: (GSCSVariable*)variable;

@end

#endif //_GS_CS_SIMPLEX_SOLVER_H