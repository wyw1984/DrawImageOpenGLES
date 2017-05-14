//
//  ViewController.m
//  DrawImageOpenGLES
//
//  Created by yanwu wei on 2017/5/5.
//  Copyright © 2017年 Ivan. All rights reserved.
//

#import "ViewController.h"
#import "ShaderOperations.h"

@interface ViewController ()
{
    EAGLContext *_eaglContext; // OpenGL context,管理使用opengl es进行绘制的状态,命令及资源
    CAEAGLLayer *_eaglLayer;
    
    GLuint _colorRenderBuffer; // 渲染缓冲区
    GLuint _frameBuffer; // 帧缓冲区
    
    GLuint _glProgram;
    GLuint _positionSlot; // 顶点
    GLuint _textureSlot;  // 纹理
    GLuint _textureCoordsSlot; // 纹理坐标
    
    GLuint _textureID; // 纹理ID
    
    CGRect _frameCAEAGLLayer;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    UIImage *originImage = [UIImage imageNamed:@"fengjing.jpeg"];
    
    _frameCAEAGLLayer = CGRectMake(10, 50, self.view.frame.size.width - 20, originImage.size.height*1.0/originImage.size.width * (self.view.frame.size.width - 20));
    
    [self setupForOpenGLES];

    [self didDrawImageViaOpenGLES:originImage];
    
}


#pragma mark - setupForOpenGLES

- (void)setupForOpenGLES
{
    [self setupOpenGLContext];
    [self setupCAEAGLLayer:_frameCAEAGLLayer];
    
    [self tearDownOpenGLBuffers];
    [self setupOpenGLBuffers];
    
    glClearColor(1.0f, 1.0f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glViewport(0, 0, CGRectGetWidth(_frameCAEAGLLayer), CGRectGetHeight(_frameCAEAGLLayer));
    
    [self setupBlendMode];
    
    [self processShaders];
}

- (void)setupOpenGLContext {
    //setup context, 渲染上下文，管理所有绘制的状态，命令及资源信息。
    _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2]; //opengl es 2.0
    [EAGLContext setCurrentContext:_eaglContext]; //设置为当前上下文。
}

- (void)setupCAEAGLLayer:(CGRect)rect {
    _eaglLayer = [CAEAGLLayer layer];
    _eaglLayer.frame = rect;
    _eaglLayer.opaque = YES;
    
    _eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],kEAGLDrawablePropertyRetainedBacking,kEAGLColorFormatRGBA8,kEAGLDrawablePropertyColorFormat, nil];
    [self.view.layer addSublayer:_eaglLayer];
}

- (void)tearDownOpenGLBuffers {
    //destory render and frame buffer
    if (_colorRenderBuffer) {
        glDeleteRenderbuffers(1, &_colorRenderBuffer);
        _colorRenderBuffer = 0;
    }
    
    if (_frameBuffer) {
        glDeleteFramebuffers(1, &_frameBuffer);
        _frameBuffer = 0;
    }
}

- (void)setupOpenGLBuffers {
    //先要renderbuffer，然后framebuffer，顺序不能互换。
    
    // OpenGlES共有三种：colorBuffer，depthBuffer，stencilBuffer。
    // 生成一个renderBuffer，id是_colorRenderBuffer
    glGenRenderbuffers(1, &_colorRenderBuffer);
    // 设置为当前renderBuffer
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    //为color renderbuffer 分配存储空间
    [_eaglContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
    
    // FBO用于管理colorRenderBuffer，离屏渲染
    glGenFramebuffers(1, &_frameBuffer);
    //设置为当前framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
    // 将 _colorRenderBuffer 装配到 GL_COLOR_ATTACHMENT0 这个装配点上
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderBuffer);
}

- (void)setupBlendMode {
    glEnable(GL_BLEND);// 启用混合
    glBlendFunc(GL_ONE, GL_ZERO); // 源色将覆盖目标色
}

- (void)processShaders {
    _glProgram = [ShaderOperations compileShaders:@"Vertex" shaderFragment:@"Fragment"];
    
    glUseProgram(_glProgram);
    
    // 需要三个参数, 跟Shader中的一一对应。
    // Position: 将颜色放置在CAEAGLLayer上的哪个位置
    // Texture: 图像的纹理
    // TextureCoords: 图像的纹理坐标，即图像纹理的哪一块颜色
    _positionSlot = glGetAttribLocation(_glProgram, "Position");
    _textureSlot = glGetUniformLocation(_glProgram, "Texture");
    _textureCoordsSlot = glGetAttribLocation(_glProgram, "TextureCoords");
}

#pragma mark - didDrawImageViaOpenGLES

- (void)didDrawImageViaOpenGLES:(UIImage *)image {
    // 将image绑定到GL_TEXTURE_2D上，即传递到GPU中
    _textureID = [self setupTexture:image];
    // 此时，纹理数据就可看做已经在纹理对象_textureID中了，使用时从中取出即可
    
    // 第一行和第三行不是严格必须的，默认使用GL_TEXTURE0作为当前激活的纹理单元
    glActiveTexture(GL_TEXTURE5); // 指定纹理单元GL_TEXTURE5
    glBindTexture(GL_TEXTURE_2D, _textureID); // 绑定，即可从_textureID中取出图像数据。
    glUniform1i(_textureSlot, 5); // 与纹理单元的序号对应
    
    // 渲染需要的数据要从GL_TEXTURE_2D中得到。
    // GL_TEXTURE_2D与_textureID已经绑定
    [self render];
    
    glBindTexture(GL_TEXTURE_2D, 0);
    [_eaglContext presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark - setupTexture

/**
 *  加载image, 使用CoreGraphics将位图以RGBA格式存放. 将UIImage图像数据转化成OpenGL ES接受的数据.
 *  然后在GPU中将图像纹理传递给GL_TEXTURE_2D。
 *  @return 返回的是纹理对象，该纹理对象暂时未跟GL_TEXTURE_2D绑定（要调用bind）。
 *  即GL_TEXTURE_2D中的图像数据都可从纹理对象中取出。
 */
- (GLuint)setupTexture:(UIImage *)image {
    CGImageRef cgImageRef = [image CGImage];
    GLuint width = (GLuint)CGImageGetWidth(cgImageRef);
    GLuint height = (GLuint)CGImageGetHeight(cgImageRef);
    CGRect rect = CGRectMake(0, 0, width, height);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    void *imageData = malloc(width * height * 4);
    CGContextRef context = CGBitmapContextCreate(imageData, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1.0f, -1.0f);
    CGColorSpaceRelease(colorSpace);
    CGContextClearRect(context, rect);
    CGContextDrawImage(context, rect, cgImageRef);
    
    glEnable(GL_TEXTURE_2D);
    
    /**
     *  GL_TEXTURE_2D表示操作2D纹理
     *  创建纹理对象，
     *  绑定纹理对象，
     */
    
    GLuint textureID;
    glGenTextures(1, &textureID);
    glBindTexture(GL_TEXTURE_2D, textureID);
    
    /**
     *  纹理过滤函数
     *  图象从纹理图象空间映射到帧缓冲图象空间(映射需要重新构造纹理图像,这样就会造成应用到多边形上的图像失真),
     *  这时就可用glTexParmeteri()函数来确定如何把纹理象素映射成像素.
     *  如何把图像从纹理图像空间映射到帧缓冲图像空间（即如何把纹理像素映射成像素）
     */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); // S方向上的贴图模式
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); // T方向上的贴图模式
    // 线性过滤：使用距离当前渲染像素中心最近的4个纹理像素加权平均值
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    /**
     *  将图像数据传递给到GL_TEXTURE_2D中, 因其于textureID纹理对象已经绑定，所以即传递给了textureID纹理对象中。
     *  glTexImage2d会将图像数据从CPU内存通过PCIE上传到GPU内存。
     *  不使用PBO时它是一个阻塞CPU的函数，数据量大会卡。
     */
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
    
    // 结束后要做清理
    glBindTexture(GL_TEXTURE_2D, 0); //解绑
    CGContextRelease(context);
    free(imageData);
    
    return textureID;
}

#pragma mark - render

- (void)render {
    [self renderVertices];
    //  [self renderUsingIndex];
    //  [self renderUsingVBO];
    //[self renderUsingIndexVBO];
}

/**
 *  直接取出对应纹理坐标TextureCoords
 *  根据顶点数据和纹理坐标数据（一一对应），填充到对应的坐标位置Positon中
 *  注意：二者的坐标系不同。
 */
- (void)renderVertices {
    GLfloat texCoords[] = {
        0, 0,//左下
        1, 0,//右下
        0, 1,//左上
        1, 1,//右上
    };
    glVertexAttribPointer(_textureCoordsSlot, 2, GL_FLOAT, GL_FALSE, 0, texCoords);
    glEnableVertexAttribArray(_textureCoordsSlot);
    
    
    GLfloat vertices[] = {
        -1, -1, 0,   //左下
        1,  -1, 0,   //右下
        -1, 1,  0,   //左上
        1,  1,  0 }; //右上
    glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE, 0, vertices);
    glEnableVertexAttribArray(_positionSlot);
    
    // 一旦纹理数据准备好，两个坐标系的顶点位置一一对应好。
    // 就直接绘制顶点即可, 具体的绘制方式就与纹理坐标和纹理数据没有关系了。
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
