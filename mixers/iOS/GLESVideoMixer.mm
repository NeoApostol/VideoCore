/*
 
 Video Core
 Copyright (C) 2014 James G. Hurley
 
 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2.1 of the License, or (at your option) any later version.
 
 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
 USA
 
 */


#include <videocore/mixers/iOS/GLESVideoMixer.h>
#include <videocore/sources/iOS/GLESUtil.h>
#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#import <UIKit/UIKit.h>
#include <videocore/sources/iOS/GLESSource.h>
#include <CoreVideo/CoreVideo.h>


#include <glm/gtc/matrix_transform.hpp>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)


#define PERF_GL(x, dispatch) do {\
                                m_glJobQueue.dispatch([=](){\
                                    EAGLContext* cur = [EAGLContext currentContext];\
                                    if(m_glesCtx) {\
                                        [EAGLContext setCurrentContext:(EAGLContext*)m_glesCtx];\
                                    }\
                                    x ;\
                                    [EAGLContext setCurrentContext:cur];\
                                });\
                            } while(0)
#define PERF_GL_sync(x) PERF_GL((x), enqueue_sync);
#define PERF_GL_async(x) PERF_GL((x), enqueue);



namespace videocore { namespace iOS {
 
    GLESVideoMixer::GLESVideoMixer( int frame_w, int frame_h, double frameDuration )
    : m_frameW(frame_w), m_frameH(frame_h), m_bufferDuration(frameDuration), m_exiting(false), m_glesCtx(nullptr)
    {
        m_glJobQueue.set_name("com.videocore.composite");

        
        PERF_GL_sync({
            
            this->setupGLES();
            
        });
        
        m_mixThread = std::thread([this](){ this->mixThread(); });
    
    }
    
    GLESVideoMixer::~GLESVideoMixer()
    {
        m_output.reset();
        m_exiting = true;
        m_mixThreadCond.notify_all();
        PERF_GL_sync({
            glDeleteProgram(m_prog);
            glDeleteFramebuffers(2, m_fbo);
            glDeleteBuffers(1, &m_vbo);
            glDeleteVertexArraysOES(1, &m_vao);
        });
        m_mixThread.join();
        
        for ( auto it : m_sourceBuffers )
        {
            CVPixelBufferRelease(it.second);
        }
        CVPixelBufferRelease(m_pixelBuffer[0]);
        CVPixelBufferRelease(m_pixelBuffer[1]);
        [(id)m_glesCtx release];
    }
    void
    GLESVideoMixer::setupGLES()
    {
        if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            m_glesCtx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        }
        if(!m_glesCtx) {
            m_glesCtx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        }
        if(!m_glesCtx) {
            std::cerr << "Error! Unable to create an OpenGL ES 2.0 or 3.0 Context!" << std::endl;
            return;
        }
        [EAGLContext setCurrentContext:nil];
        [EAGLContext setCurrentContext:(EAGLContext*)m_glesCtx];
        GLESSource::excludeFromCapture(m_glesCtx);
        
        NSDictionary* pixelBufferOptions = @{  (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                               (NSString*) kCVPixelBufferWidthKey : @(m_frameW),
                                               (NSString*) kCVPixelBufferHeightKey : @(m_frameH),
                                               (NSString*) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                               (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{}};
        
        CVPixelBufferCreate(kCFAllocatorDefault, m_frameW, m_frameH, kCVPixelFormatType_32BGRA, (CFDictionaryRef)pixelBufferOptions, &m_pixelBuffer[0]);
        CVPixelBufferCreate(kCFAllocatorDefault, m_frameW, m_frameH, kCVPixelFormatType_32BGRA, (CFDictionaryRef)pixelBufferOptions, &m_pixelBuffer[1]);
        
        CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (EAGLContext*)this->m_glesCtx, NULL, &this->m_textureCache);
        glGenFramebuffers(2, this->m_fbo);
        for(int i = 0 ; i < 2 ; ++i) {
            CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, this->m_textureCache, this->m_pixelBuffer[i], NULL, GL_TEXTURE_2D, GL_RGBA, m_frameW, m_frameH, GL_BGRA, GL_UNSIGNED_BYTE, 0, &m_texture[i]);
            
            this->m_prog = build_program(s_vs_mat, s_fs);
            
            glBindTexture(GL_TEXTURE_2D, CVOpenGLESTextureGetName(m_texture[i]));
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glBindFramebuffer(GL_FRAMEBUFFER, m_fbo[i]);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(m_texture[i]), 0);
            
        }
        
        GL_FRAMEBUFFER_STATUS(__LINE__);
        
        glGenBuffers(1, &this->m_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, this->m_vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(s_vbo), s_vbo, GL_STATIC_DRAW);
        
        glUseProgram(this->m_prog);
        glGenVertexArraysOES(1, &this->m_vao);
        glBindVertexArrayOES(this->m_vao);
        
        this->m_uMat = glGetUniformLocation(this->m_prog, "uMat");
        
        int attrpos = glGetAttribLocation(this->m_prog, "aPos");
        int attrtex = glGetAttribLocation(this->m_prog, "aCoord");
        int unitex = glGetUniformLocation(this->m_prog, "uTex0");
        glUniform1i(unitex, 0);
        glEnableVertexAttribArray(attrpos);
        glEnableVertexAttribArray(attrtex);
        glVertexAttribPointer(attrpos, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 4, BUFFER_OFFSET(0));
        glVertexAttribPointer(attrtex, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 4, BUFFER_OFFSET(8));
        glDisable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_SCISSOR_TEST);
        glViewport(0, 0, m_frameW,m_frameH);
        glClearColor(0.05,0.05,0.07,1.0);

    }
    void
    GLESVideoMixer::registerSource(std::shared_ptr<ISource> source, size_t bufferSize)
    {
        const auto hash = std::hash< std::shared_ptr<ISource> > () (source);
        bool registered = false;
        
        for ( auto it : m_sources) {
            auto lsource = it.lock();
            if(lsource) {
                const auto shash = std::hash< std::shared_ptr<ISource> >() (lsource);
                if(shash == hash) {
                    registered = true;
                    break;
                }
            }
        }
        if(!registered)
        {
            m_sources.push_back(source);
        }
    }
    void
    GLESVideoMixer::releaseBuffer(std::weak_ptr<ISource> source)
    {
        const auto h = hash(source);
        auto it = m_sourceBuffers.find(h) ;
        if(it != m_sourceBuffers.end()) {
            CVPixelBufferRelease(it->second);
            m_sourceBuffers.erase(it);
        }
        
    }
    void
    GLESVideoMixer::unregisterSource(std::shared_ptr<ISource> source)
    {
        releaseBuffer(source);
        
        auto it = m_sources.begin();
        const auto h = std::hash<std::shared_ptr<ISource> >()(source);
        for ( ; it != m_sources.end() ; ++it ) {

            const auto shash = hash(*it);
            
            if(h == shash) {
                m_sources.erase(it);
                break;
            }
            
        }
        for ( int i = 0 ; i < VideoLayer_Count ; ++i )
        {
            for ( auto iit = m_layerMap[i].begin() ; iit!= m_layerMap[i].end() ; ++iit) {
                if((*iit) == h) {
                    m_layerMap[i].erase(iit);
                    break;
                }
            }
        }
        
    }
    void
    GLESVideoMixer::pushBuffer(const uint8_t *const data, size_t size, videocore::IMetadata &metadata)
    {
        VideoBufferMetadata & md = dynamic_cast<VideoBufferMetadata&>(metadata);
        VideoLayer_t layer = md.getData<kVideoMetadataLayer>();
        
        std::weak_ptr<ISource> source = md.getData<kVideoMetadataSource>();

        const auto h = hash(source);
        
        CVPixelBufferRef inPixelBuffer = (CVPixelBufferRef)data;
        
        bool refreshTexture = false;
        CVPixelBufferRef refreshRef = NULL;
        auto pbit = m_sourceBuffers.find(h);
        
        if(pbit == m_sourceBuffers.end() || pbit->second != inPixelBuffer) {
            refreshRef = CVPixelBufferRetain(inPixelBuffer);
            refreshTexture = true;
        }
        
        if(refreshTexture) {
            PERF_GL_async({
                
                releaseBuffer(source);
                m_sourceBuffers[h] = refreshRef;
                
                auto it_buf = this->m_sourceBuffers.find(h);
                if(it_buf != this->m_sourceBuffers.end()) {
                    CVPixelBufferRef pixelBuffer = it_buf->second;
                    
                    auto it = this->m_sourceTextures.find(h);
                    if(it != this->m_sourceTextures.end()) {
                        CFRelease(this->m_sourceTextures[h]);
                        this->m_sourceTextures.erase(it);
                    }
                    CVOpenGLESTextureRef tex = NULL;
                    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
                    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
                    bool is32bit = true;
                    if(format == kCVPixelFormatType_16LE565) is32bit = false;
                    
                    CVReturn ret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                                this->m_textureCache,
                                                                                pixelBuffer,
                                                                                NULL,
                                                                                GL_TEXTURE_2D,
                                                                                is32bit ? GL_RGBA : GL_RGB,
                                                                                CVPixelBufferGetWidth(pixelBuffer),
                                                                                CVPixelBufferGetHeight(pixelBuffer),
                                                                                is32bit ? GL_BGRA : GL_RGB,
                                                                                is32bit ? GL_UNSIGNED_BYTE : GL_UNSIGNED_SHORT_5_6_5,
                                                                                0,
                                                                                &tex);
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
                    if(ret == kCVReturnSuccess) {
                        this->m_sourceTextures[h] = tex;
                        glBindTexture(GL_TEXTURE_2D, CVOpenGLESTextureGetName(this->m_sourceTextures[h]));
                        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                    }
                }
                auto it = std::find(m_layerMap[layer].begin(), m_layerMap[layer].end(), h);
                if(it == m_layerMap[layer].end()) {
                    m_layerMap[layer].push_back(h);
                }

                CVOpenGLESTextureCacheFlush(this->m_textureCache, 0);
            });
        }
    }
    void
    GLESVideoMixer::setOutput(std::shared_ptr<IOutput> output)
    {
        m_output = output;
    }
    const std::size_t
    GLESVideoMixer::hash(std::weak_ptr<ISource> source) const
    {
        const auto l = source.lock();
        if (l) {
            return std::hash< std::shared_ptr<ISource> >()(l);
        }
        return 0;
    }
    void
    GLESVideoMixer::setSourceProperties(std::weak_ptr<ISource> source, videocore::SourceProperties properties)
    {
        auto h = hash(source);
        m_sourceProperties[h] = properties;
        glm::mat4 mat = glm::mat4(1.f);
        
        float x = properties.x * 2.f - 1.f;
        float y = properties.y * 2.f - 1.f;
        
        
        mat = glm::translate(mat, glm::vec3(x, y, 0.f));
        mat = glm::scale(mat, glm::vec3(properties.width, properties.height, 1.f));
                                        
        m_sourceMats[h] = mat;
        
    }
    void
    GLESVideoMixer::mixThread()
    {
        const auto us = std::chrono::microseconds(static_cast<long long>(m_bufferDuration * 1000000.));
        
        pthread_setname_np("com.videocore.compositeloop");
        
        int current_fb = 0;
        
        bool locked[2] = {false};
        
        while(!m_exiting.load())
        {
            std::unique_lock<std::mutex> l (m_mutex);
            auto wt = std::chrono::high_resolution_clock::now() + us;
            
            locked[current_fb] = true;
            
            PERF_GL_async({

                glPushGroupMarkerEXT(0, "Mobcrush.mix");
                CVPixelBufferLockBaseAddress(this->m_pixelBuffer[current_fb], 0);
                
                glBindFramebuffer(GL_FRAMEBUFFER, this->m_fbo[current_fb]);
                
                glClear(GL_COLOR_BUFFER_BIT);
                glBindBuffer(GL_ARRAY_BUFFER, this->m_vbo);
                glBindVertexArrayOES(this->m_vao);
                glUseProgram(this->m_prog);
                
                for ( int i = 0 ; i < VideoLayer_Count ; ++i) {
                    
                    for ( auto it = this->m_layerMap[i].begin() ; it != this->m_layerMap[i].end() ; ++ it) {
                        CVPixelBufferLockBaseAddress(this->m_sourceBuffers[*it], kCVPixelBufferLock_ReadOnly); // Lock, read-only.
                        CVOpenGLESTextureRef texture = NULL;
                        auto iTex = this->m_sourceTextures.find(*it);
                        if(iTex == this->m_sourceTextures.end()) continue;
                        texture = iTex->second;

                        if(this->m_sourceProperties[*it].blends) {
                            glEnable(GL_BLEND);
                            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                        }
                        glUniformMatrix4fv(m_uMat, 1, GL_FALSE, &this->m_sourceMats[*it][0][0]);
                        glBindTexture(GL_TEXTURE_2D, CVOpenGLESTextureGetName(texture));
                        glDrawArrays(GL_TRIANGLES, 0, 6);
                        GL_ERRORS(__LINE__);
                        CVPixelBufferUnlockBaseAddress(this->m_sourceBuffers[*it], kCVPixelBufferLock_ReadOnly);
                        if(this->m_sourceProperties[*it].blends) {
                            glDisable(GL_BLEND);
                        }
                    }
                }
                glFlush();
                glPopGroupMarkerEXT();
                if(locked[!current_fb])
                    CVPixelBufferUnlockBaseAddress(this->m_pixelBuffer[!current_fb], 0);
                
                auto lout = this->m_output.lock();
                if(lout) {
                    
                    MetaData<'vide'> md(this->m_bufferDuration);
                    lout->pushBuffer((uint8_t*)this->m_pixelBuffer[!current_fb], sizeof(this->m_pixelBuffer[!current_fb]), md);
                }

                
            });
            current_fb = !current_fb;
            m_mixThreadCond.wait_until(l, wt);
                
        }
    }
}
}