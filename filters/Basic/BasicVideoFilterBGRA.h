/*
 
 Video Core
 Copyright (c) 2014 James G. Hurley
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */
#ifndef videocore_BasicVideoFilterBGRA_h
#define videocore_BasicVideoFilterBGRA_h

#include <videocore/filters/IVideoFilter.hpp>

namespace videocore {
    namespace filters {
        class BasicVideoFilterBGRA : public IVideoFilter {
            
        public:
            BasicVideoFilterBGRA();
            ~BasicVideoFilterBGRA();
        
        public:
            virtual void initialize();
            virtual bool initialized();
            
            virtual void apply();
        
            
        public:
            virtual void incomingMatrix(float matrix[16]);
            virtual void imageDimensions(float w, float h);
            
        protected:
            /*! IVideoFilter */
            
            const char * const vertexKernel() const ;
            const char * const pixelKernel() const ;
            
        public:
            
        };
    }
}

#endif /* defined(videocore_BasicVideoFilterBGRA_h) */