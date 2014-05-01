//
//  ICPDFView.h
//  iConsult Enterprise
//
//  Created by finucane on 1/20/13.
//  Donated to the public domain.
//
//

#import <UIKit/UIKit.h>
#import "ICPatient.h"
#import "ICConsult.h"

@class ICPDFView;

/*
 the ICPDF delegate is responsible for getting a signature image or date string from the user
 and setting the button image or string with setSignature or setDate. this separates
 whatever UI that requires from ICPDFView.
 */
@protocol ICPDFViewDelegate

-(void)pdfViewDidTapSignature:(ICPDFView *)pdfView button:(UIButton *)button;
-(void)pdfViewDidTapDate:(ICPDFView *)aPdfView button:(UIButton *)button maxDate:(NSDate*)maxDate;

@end

@interface ICPDFView : UIView <UITextFieldDelegate, UITextViewDelegate>
{
@private
    NSMutableArray *signatureButtons;
    NSMutableArray *referenceButtons;
    NSMutableArray *radioButtons;
    NSMutableArray *requiredFields;
    NSMutableArray *requiredFieldsSeen;
    NSMutableDictionary *radioButtonGroups;
    NSMutableArray *signatures;
    NSMutableArray *signaturePointers;
    ICConsult *consult;
    ICPatient *patient;
    NSString *videoTitle;
    UIColor *fieldBackgroundColor;
    UIColor *signatureBackgroundColor;
    __weak id <ICPDFViewDelegate>delegate;
    UIView*activeField;
}

-(id)initWithPage:(CGPDFPageRef)page delegate:(id <ICPDFViewDelegate>)delegate consult:(ICConsult *)consult patient:(ICPatient*)patient videoTitle:(NSString*)videoTitle;
-(void)setSignature:(UIImage *)image forButton:(UIButton *)button;
-(void)setDate:(NSDate *)date forButton:(UIButton *)button;

@property (nonatomic, readonly) NSInteger numRequiredFields;

-(NSData *)pdf;
-(UIImage *)pdfToImage;
-(UIView *)activeField;
@end
