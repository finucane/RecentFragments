//
//  insist.h
//  iConsult Enterprise
//
//  Created by finucane on 1/14/13.
//  Donated to the public domain.
//
//


/*
  easy to type macros for things that should never happen but have to be checked anyway. they can be handled
  in the main loop in a top level exception handler when we get around to it.
 */

#ifdef DEBUG

#define insist(e) if(!(e)) [NSException raise: @"assertion failed." format: @"%@:%d (%s)", [[NSString stringWithCString:__FILE__ encoding:NSUTF8StringEncoding] lastPathComponent], __LINE__, #e]

#else

#define insist(e)

#endif
