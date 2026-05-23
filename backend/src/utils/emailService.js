import nodemailer from 'nodemailer';
import os from 'os';
import logger from '../config/logger.js';

/**
 * YSHOP Email Service
 * Handles all email communications including verification, password reset, etc.
 * Supports multiple email providers and languages
 */

class EmailService {
  constructor() {
    this.transporter = null;
    this.isInitialized = false;
  }

  getPublicBackendUrl() {
    const configuredUrl = process.env.PUBLIC_BACKEND_URL || process.env.BACKEND_URL || process.env.API_BASE_URL;
    if (configuredUrl && configuredUrl.trim()) {
      return configuredUrl.replace(/\/$/, '').replace(/\/api\/v1$/, '');
    }

    const hostFromEnv = process.env.BACKEND_HOST || process.env.SERVER_HOST;
    if (hostFromEnv && hostFromEnv.trim()) {
      return `http://${hostFromEnv.replace(/^https?:\/\//, '').replace(/:\d+$/, '')}:3000`;
    }

    const interfaces = os.networkInterfaces();
    const preferredNames = ['en0', 'en1', 'en2', 'wifi', 'Wi-Fi'];

    for (const interfaceName of preferredNames) {
      const addresses = interfaces[interfaceName] || [];
      for (const address of addresses) {
        if (address.family === 'IPv4' && !address.internal && address.address) {
          return `http://${address.address}:3000`;
        }
      }
    }

    for (const addresses of Object.values(interfaces)) {
      for (const address of addresses || []) {
        if (address.family === 'IPv4' && !address.internal && address.address) {
          return `http://${address.address}:3000`;
        }
      }
    }

    return 'http://mackbook.local:3000';
  }

  /**
   * Initialize email transporter
   * Supports Gmail, custom SMTP, or test account
   */
  async initialize() {
    try {
      // Try Gmail first (set env vars EMAIL_USER and EMAIL_PASSWORD)
      if (process.env.EMAIL_USER && process.env.EMAIL_PASSWORD) {
        this.transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: {
            user: process.env.EMAIL_USER,
            pass: process.env.EMAIL_PASSWORD,
          },
        });
        logger.info('✓ Email service initialized with Gmail');
      }
      // Try custom SMTP
      else if (process.env.EMAIL_HOST) {
        this.transporter = nodemailer.createTransport({
          host: process.env.EMAIL_HOST,
          port: process.env.EMAIL_PORT || 587,
          secure: process.env.EMAIL_SECURE === 'true',
          auth: {
            user: process.env.EMAIL_USER,
            pass: process.env.EMAIL_PASSWORD,
          },
        });
        logger.info('✓ Email service initialized with custom SMTP');
      }
      // Fallback: create test account for development
      else {
        logger.warn('⚠ No email configuration found. Using test mode.');
        this.transporter = nodemailer.createTransport({
          host: 'smtp.ethereal.email',
          port: 587,
          secure: false,
          auth: {
            user: process.env.EMAIL_USER || 'test@ethereal.email',
            pass: process.env.EMAIL_PASSWORD || 'test-password',
          },
        });
      }

      this.isInitialized = true;
      return true;
    } catch (error) {
      logger.error('✗ Failed to initialize email service:', error.message);
      throw error;
    }
  }

  /**
   * Send verification email
   * @param {string} email - Recipient email
   * @param {string} token - Verification token
   * @param {string} userName - User's display name
   * @param {string} lang - Language (en, ar)
   */
  async sendVerificationEmail(email, token, userName = 'User', lang = 'en') {
    if (!this.isInitialized) {
      throw new Error('Email service not initialized');
    }

    const backendUrl = this.getPublicBackendUrl();
    const verifyLink = `${backendUrl}/api/v1/auth/verify-email?token=${token}`;

    const templates = {
      en: {
        subject: 'YSHOP - Identity Authentication Required',
        text: `Hello ${userName}, Welcome to YSHOP! Verify your email here: ${verifyLink}`,
        html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; background: #FAFAFA; line-height: 1.6; color: #1A1A1A; }
    .wrapper { background: #FAFAFA; padding: 40px 20px; }
    .container { max-width: 580px; margin: 0 auto; background: white; border-radius: 4px; overflow: hidden; border: 1px solid #EEEEEE; box-shadow: 0 4px 20px rgba(0,0,0,0.03); }
    .header { background: #1A1A1A; padding: 50px 30px; text-align: center; }
    .header h1 { font-size: 26px; font-weight: 900; color: white; margin: 0; letter-spacing: 8px; }
    .badge { display: inline-block; color: #42A5F5; padding: 6px 12px; font-size: 10px; font-weight: bold; margin-top: 10px; letter-spacing: 3px; text-transform: uppercase; }
    .content { padding: 40px 30px; }
    .greeting { font-size: 20px; font-weight: 300; color: #1A1A1A; margin-bottom: 20px; border-left: 3px solid #42A5F5; padding-left: 15px; }
    .message { font-size: 14px; color: #555; line-height: 1.8; margin-bottom: 25px; }
    .button-wrapper { text-align: center; margin: 35px 0; }
    .button { display: inline-block; padding: 18px 40px; background: #1A1A1A; color: white !important; text-decoration: none; border-radius: 2px; font-weight: bold; font-size: 13px; letter-spacing: 2px; transition: all 0.3s ease; }
    .divider { height: 1px; background: #F0F0F0; margin: 30px 0; }
    .code-section { background: #F9F9F9; padding: 20px; border-radius: 4px; border-left: 4px solid #42A5F5; }
    .code-label { font-size: 11px; font-weight: bold; color: #42A5F5; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; }
    .code { background: white; padding: 12px; border-radius: 2px; font-family: 'Courier New', monospace; font-size: 11px; color: #666; word-break: break-all; border: 1px solid #EEE; }
    .footer { background: #FFFFFF; padding: 30px; border-top: 1px solid #F5F5F5; text-align: center; font-size: 11px; color: #AAA; letter-spacing: 1px; }
    .footer-link { color: #42A5F5; text-decoration: none; }
    .warning { font-size: 12px; color: #888; margin-top: 20px; font-style: italic; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <h1>YSHOP</h1>
        <span class="badge">Security Portal</span>
      </div>
      
      <div class="content">
        <p class="greeting">Identity Verification</p>
        
        <p class="message">
          Hello ${userName}. Welcome to the YSHOP ecosystem. To ensure the security of your account and activate your premium access, please authenticate your email address.
        </p>
        
        <div class="button-wrapper">
          <a href="${verifyLink}" class="button">AUTHENTICATE NOW</a>
        </div>
        
        <p class="warning">
          Note: This authentication request expires in 24 hours.
        </p>
        
        <div class="divider"></div>
        
        <p class="message" style="font-size: 12px; color: #BBB; text-align: center;">
          If you did not initiate this request, please disregard this communication.
        </p>
      </div>
      
      <div class="footer">
        <p style="margin-bottom: 10px;">© 2026 <strong>YSHOP</strong>. ALL RIGHTS RESERVED.</p>
        <p>CONCIERGE: <a href="mailto:${process.env.EMAIL_USER || 'support@yshop.com'}" class="footer-link">SUPPORT@YSHOP.COM</a></p>
      </div>
    </div>
  </div>
</body>
</html>
        `,
      },
      ar: {
        subject: 'YSHOP - مطلوب توثيق الهوية الرقمية',
        text: `مرحبا ${userName}, يرجى التحقق من بريدك الإلكتروني لتفعيل حسابك في YSHOP: ${verifyLink}`,
        html: `
<!DOCTYPE html>
<html dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Arial', sans-serif; background: #FAFAFA; line-height: 1.6; color: #1A1A1A; }
    .wrapper { background: #FAFAFA; padding: 40px 20px; }
    .container { max-width: 580px; margin: 0 auto; background: white; border-radius: 4px; overflow: hidden; border: 1px solid #EEEEEE; box-shadow: 0 4px 20px rgba(0,0,0,0.03); }
    .header { background: #1A1A1A; padding: 50px 30px; text-align: center; }
    .header h1 { font-size: 26px; font-weight: 900; color: white; margin: 0; letter-spacing: 8px; }
    .badge { display: inline-block; color: #42A5F5; padding: 6px 12px; font-size: 10px; font-weight: bold; margin-top: 10px; letter-spacing: 2px; text-transform: uppercase; }
    .content { padding: 40px 30px; text-align: right; }
    .greeting { font-size: 20px; font-weight: 300; color: #1A1A1A; margin-bottom: 20px; border-right: 3px solid #42A5F5; padding-right: 15px; }
    .message { font-size: 14px; color: #555; line-height: 1.8; margin-bottom: 25px; }
    .button-wrapper { text-align: center; margin: 35px 0; }
    .button { display: inline-block; padding: 18px 40px; background: #1A1A1A; color: white !important; text-decoration: none; border-radius: 2px; font-weight: bold; font-size: 13px; letter-spacing: 2px; transition: all 0.3s ease; }
    .divider { height: 1px; background: #F0F0F0; margin: 30px 0; }
    .code-section { background: #F9F9F9; padding: 20px; border-radius: 4px; border-right: 4px solid #42A5F5; }
    .code-label { font-size: 11px; font-weight: bold; color: #42A5F5; margin-bottom: 8px; text-transform: uppercase; }
    .code { background: white; padding: 12px; border-radius: 2px; font-family: 'Courier New', monospace; font-size: 11px; color: #666; word-break: break-all; border: 1px solid #EEE; direction: ltr; text-align: left; }
    .footer { background: #FFFFFF; padding: 30px; border-top: 1px solid #F5F5F5; text-align: center; font-size: 11px; color: #AAA; letter-spacing: 1px; }
    .footer-link { color: #42A5F5; text-decoration: none; }
    .warning { font-size: 12px; color: #888; margin-top: 20px; font-style: italic; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <h1>YSHOP</h1>
        <span class="badge">بوابة التوثيق الآمنة</span>
      </div>
      
      <div class="content">
        <p class="greeting">توثيق الهوية الرقمية</p>
        
        <p class="message">
          مرحباً ${userName}. أهلاً بك في نظام YSHOP المتكامل. لضمان أمن حسابك وتفعيل وصولك الحصري، يرجى تأكيد ملكية بريدك الإلكتروني.
        </p>
        
        <div class="button-wrapper">
          <a href="${verifyLink}" class="button">توثيق الحساب الآن</a>
        </div>
        
        <p class="message" style="text-align: center; font-size: 12px; color: #999;">
          أو استخدم رابط الوصول المباشر:
        </p>
        
        <div class="code-section">
          <div class="code-label">رابط التوثيق الآمن</div>
          <div class="code">${verifyLink}</div>
        </div>
        
        <p class="warning">
          ملاحظة: تنتهي صلاحية طلب التوثيق خلال 24 ساعة.
        </p>
        
        <div class="divider"></div>
        
        <p class="message" style="font-size: 12px; color: #BBB; text-align: center;">
          إذا لم تكن أنت من قام بهذا الطلب، يرجى تجاهل هذه الرسالة.
        </p>
      </div>
      
      <div class="footer">
        <p style="margin-bottom: 10px;">© 2026 <strong>YSHOP</strong>. جميع الحقوق محفوظة.</p>
        <p>مركز الدعم: <a href="mailto:${process.env.EMAIL_USER || 'support@yshop.com'}" class="footer-link">SUPPORT@YSHOP.COM</a></p>
      </div>
    </div>
  </div>
</body>
</html>
        `,
      },
    };

    const template = templates[lang] || templates.en;

    try {
      const mailOptions = {
        from: process.env.EMAIL_FROM || process.env.EMAIL_USER || 'noreply@yshop.com',
        to: email,
        subject: template.subject,
        text: template.text,
        html: template.html,
      };

      const info = await this.transporter.sendMail(mailOptions);

      logger.info(`✓ Verification email sent to ${email}`);

      // For development/testing
      if (process.env.NODE_ENV !== 'production') {
        logger.debug(`Preview URL: ${nodemailer.getTestMessageUrl(info)}`);
      }

      return true;
    } catch (error) {
      logger.error(`✗ Failed to send email to ${email}:`, error.message);
      throw error;
    }
  }

  /**
   * Send password reset email
   */
  async sendPasswordResetEmail(email, resetToken, userName = 'User', lang = 'en') {
    if (!this.isInitialized) {
      throw new Error('Email service not initialized');
    }

    const protocol = process.env.NODE_ENV === 'production' ? 'https' : 'http';
    const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:3000';
    const resetLink = `${frontendUrl}/reset-password?token=${resetToken}`;

    const templates = {
      en: {
        subject: 'YSHOP - Password Reset Request',
        text: `
Hello ${userName},

We received a request to reset your password.

Please click the link below to reset your password:
${resetLink}

This link will expire in 1 hour.

If you did not request this reset, please ignore this email.

Best regards,
YSHOP Team
        `,
        html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { background: #f9f9f9; padding: 30px; }
    .button { display: inline-block; padding: 12px 30px; background-color: #667eea; color: white; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 20px 0; }
    .footer { background: #333; color: white; padding: 20px; text-align: center; font-size: 12px; border-radius: 0 0 5px 5px; }
    .code { background: #f0f0f0; padding: 10px; border-radius: 3px; font-family: monospace; word-break: break-all; }
    .warning { color: #666; font-size: 12px; margin-top: 15px; color: #d9534f; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>YSHOP</h1>
    </div>
    <div class="content">
      <h2>Password Reset Request</h2>
      <p>Hello ${userName},</p>
      <p>We received a request to reset your password.</p>
      <p>Click the button below to reset your password:</p>
      <center>
        <a href="${resetLink}" class="button">Reset Password</a>
      </center>
      <p>Or copy and paste this link in your browser:</p>
      <div class="code">${resetLink}</div>
      <p class="warning">This link will expire in 1 hour.</p>
      <p class="warning">If you did not request this reset, please ignore this email and your password will remain unchanged.</p>
    </div>
    <div class="footer">
      <p>&copy; 2026 YSHOP. All rights reserved.</p>
      <p>Questions? Contact us at ${process.env.EMAIL_USER || 'support@yshop.com'}</p>
    </div>
  </div>
</body>
</html>
        `,
      },
      ar: {
        subject: 'YSHOP - طلب إعادة تعيين كلمة المرور',
        text: `
مرحا ${userName},

لقد تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك.

يرجى النقر على الرابط أدناه لإعادة تعيين كلمة المرور:
${resetLink}

سينتهي صلاحية هذا الرابط في ساعة واحدة.

إذا لم تطلب هذه العملية، يرجى تجاهل هذا البريد.

مع أطيب التحيات,
فريق YSHOP
        `,
        html: `
<!DOCTYPE html>
<html dir="rtl">
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Arial', sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { background: #f9f9f9; padding: 30px; }
    .button { display: inline-block; padding: 12px 30px; background-color: #667eea; color: white; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 20px 0; }
    .footer { background: #333; color: white; padding: 20px; text-align: center; font-size: 12px; border-radius: 0 0 5px 5px; }
    .code { background: #f0f0f0; padding: 10px; border-radius: 3px; font-family: monospace; word-break: break-all; }
    .warning { color: #666; font-size: 12px; margin-top: 15px; color: #d9534f; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>YSHOP</h1>
    </div>
    <div class="content">
      <h2>طلب إعادة تعيين كلمة المرور</h2>
      <p>مرحا ${userName},</p>
      <p>لقد تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك.</p>
      <p>انقر على الزر أدناه لإعادة تعيين كلمة المرور:</p>
      <center>
        <a href="${resetLink}" class="button">إعادة تعيين كلمة المرور</a>
      </center>
      <p>أو انسخ والصق هذا الرابط في متصفحك:</p>
      <div class="code">${resetLink}</div>
      <p class="warning">سينتهي صلاحية هذا الرابط في ساعة واحدة.</p>
      <p class="warning">إذا لم تطلب هذه العملية، يرجى تجاهل هذا البريد وستبقى كلمة المرور الخاصة بك دون تغيير.</p>
    </div>
    <div class="footer">
      <p>&copy; 2026 YSHOP. جميع الحقوق محفوظة.</p>
      <p>هل لديك أسئلة؟ تواصل معنا على ${process.env.EMAIL_USER || 'support@yshop.com'}</p>
    </div>
  </div>
</body>
</html>
        `,
      },
    };

    const template = templates[lang] || templates.en;

    try {
      await this.transporter.sendMail({
        from: process.env.EMAIL_FROM || process.env.EMAIL_USER || 'noreply@yshop.com',
        to: email,
        subject: template.subject,
        text: template.text,
        html: template.html,
      });

      logger.info(`✓ Password reset email sent to ${email}`);
      return true;
    } catch (error) {
      logger.error(`✗ Failed to send password reset email to ${email}:`, error.message);
      throw error;
    }
  }

  /**
   * Send welcome email (after successful verification)
   */
  async sendWelcomeEmail(email, userName = 'User', lang = 'en') {
    if (!this.isInitialized) {
      throw new Error('Email service not initialized');
    }

    const templates = {
      en: {
        subject: 'Welcome to YSHOP — Your Journey Begins',
        html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; line-height: 1.8; color: #1A1A1A; background-color: #FAFAFA; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 40px auto; background: #FFFFFF; border: 1px solid #EEEEEE; border-radius: 4px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.02); }
    .header { background: #1A1A1A; padding: 50px 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 26px; color: #FFFFFF; letter-spacing: 8px; font-weight: 900; }
    .header p { color: #42A5F5; font-size: 10px; letter-spacing: 4px; text-transform: uppercase; margin-top: 8px; font-weight: bold; }
    .content { padding: 50px 40px; }
    .content h2 { font-size: 22px; font-weight: 300; color: #1A1A1A; margin-bottom: 25px; border-left: 3px solid #42A5F5; padding-left: 15px; }
    .content p { font-size: 15px; color: #555555; }
    .features-list { list-style: none; padding: 0; margin: 30px 0; }
    .features-list li { margin-bottom: 12px; font-size: 14px; color: #333; display: flex; align-items: center; }
    .features-list li:before { content: "•"; color: #42A5F5; font-weight: bold; display: inline-block; width: 1em; margin-left: -1em; padding-left: 15px; }
    .footer { background: #F9F9F9; color: #999999; padding: 30px; text-align: center; font-size: 11px; border-top: 1px solid #EEEEEE; letter-spacing: 1px; }
    .footer a { color: #42A5F5; text-decoration: none; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>YSHOP</h1>
      <p>Premium Ecosystem</p>
    </div>
    <div class="content">
      <h2>Welcome to the Boutique, ${userName}!</h2>
      <p>Your identity has been successfully authenticated. You now have full access to the YSHOP premium experience.</p>
      
      <p style="margin-top: 25px; font-weight: bold; color: #1A1A1A;">Exclusive Privileges:</p>
      <ul class="features-list">
        <li>Curated selections from premium global stores</li>
        <li>Real-time telemetry for all your orders</li>
        <li>Secure vault for your favorite items</li>
        <li>Priority white-glove delivery service</li>
      </ul>
      
      <p>If you require any assistance, our concierge team is at your disposal.</p>
      <p style="margin-top: 30px;">Best regards,<br><strong style="color: #1A1A1A;">YSHOP Global Team</strong></p>
    </div>
    <div class="footer">
      <p>© 2026 YSHOP. ALL RIGHTS RESERVED.</p>
      <p>Support: <a href="mailto:${process.env.EMAIL_USER || 'support@yshop.com'}">${process.env.EMAIL_USER || 'support@yshop.com'}</a></p>
    </div>
  </div>
</body>
</html>
        `,
      },
      ar: {
        subject: 'مرحباً بك في YSHOP — تبدأ رحلتك هنا',
        html: `
<!DOCTYPE html>
<html dir="rtl">
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Arial', sans-serif; line-height: 1.8; color: #1A1A1A; background-color: #FAFAFA; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 40px auto; background: #FFFFFF; border: 1px solid #EEEEEE; border-radius: 4px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.02); }
    .header { background: #1A1A1A; padding: 50px 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 26px; color: #FFFFFF; letter-spacing: 8px; font-weight: 900; }
    .header p { color: #42A5F5; font-size: 10px; letter-spacing: 4px; text-transform: uppercase; margin-top: 8px; font-weight: bold; }
    .content { padding: 50px 40px; text-align: right; }
    .content h2 { font-size: 22px; font-weight: 300; color: #1A1A1A; margin-bottom: 25px; border-right: 3px solid #42A5F5; padding-right: 15px; }
    .content p { font-size: 15px; color: #555555; }
    .features-list { list-style: none; padding: 0; margin: 30px 0; }
    .features-list li { margin-bottom: 12px; font-size: 14px; color: #333; }
    .features-list li:before { content: "•"; color: #42A5F5; font-weight: bold; margin-left: 10px; }
    .footer { background: #F9F9F9; color: #999999; padding: 30px; text-align: center; font-size: 11px; border-top: 1px solid #EEEEEE; letter-spacing: 1px; }
    .footer a { color: #42A5F5; text-decoration: none; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>YSHOP</h1>
      <p>النظام البيئي الفاخر</p>
    </div>
    <div class="content">
      <h2>مرحباً بك في بوتيك YSHOP، ${userName}!</h2>
      <p>تم تفعيل هويتك الرقمية بنجاح. يمكنك الآن الاستمتاع بكافة مميزات YSHOP الحصرية.</p>
      
      <p style="margin-top: 25px; font-weight: bold; color: #1A1A1A;">امتيازاتك الخاصة:</p>
      <ul class="features-list">
        <li>تصفح أرقى المتاجر العالمية المختارة</li>
        <li>تتبع فوري ودقيق لجميع طلباتك</li>
        <li>خزنة خاصة لعناصرك المفضلة</li>
        <li>خدمة توصيل سريعة وموثوقة</li>
      </ul>
      
      <p>إذا كان لديك أي استفسار، فريق الكونسيرج في خدمتك دائماً.</p>
      <p style="margin-top: 30px;">مع أطيب التحيات،<br><strong style="color: #1A1A1A;">فريق YSHOP العالمي</strong></p>
    </div>
    <div class="footer">
      <p>© 2026 YSHOP. جميع الحقوق محفوظة.</p>
      <p>الدعم الفني: <a href="mailto:${process.env.EMAIL_USER || 'support@yshop.com'}">${process.env.EMAIL_USER || 'support@yshop.com'}</a></p>
    </div>
  </div>
</body>
</html>
        `,
      },
    };

    const template = templates[lang] || templates.en;

    try {
      await this.transporter.sendMail({
        from: `YSHOP Premium <${process.env.EMAIL_FROM || process.env.EMAIL_USER || 'noreply@yshop.com'}>`,
        to: email,
        subject: template.subject,
        html: template.html,
      });

      logger.info(`✓ Welcome email sent to ${email}`);
      return true;
    } catch (error) {
      logger.error(`✗ Failed to send welcome email to ${email}:`, error.message);
      return false;
    }
    }

  /**
   * Send an order receipt email with attachment (PDF).
   * @param {string} email
   * @param {string} subject
   * @param {string} html
   * @param {Array} attachments - nodemailer attachments array
   */
  async sendOrderReceiptEmail(email, subject, html, attachments = []) {
    if (!this.isInitialized) {
      throw new Error('Email service not initialized');
    }

    try {
      const mailOptions = {
        from: process.env.EMAIL_FROM || process.env.EMAIL_USER || 'noreply@yshop.com',
        to: email,
        subject,
        html,
        attachments,
      };

      const info = await this.transporter.sendMail(mailOptions);
      logger.info(`✓ Receipt email sent to ${email}`);
      if (process.env.NODE_ENV !== 'production') {
        logger.debug(`Preview URL: ${nodemailer.getTestMessageUrl(info)}`);
      }
      return true;
    } catch (error) {
      logger.error(`✗ Failed to send receipt email to ${email}:`, error.message);
      throw error;
    }
  }
}
// Create singleton instance
let emailServiceInstance = null;

/**
 * Get or create email service instance
 * Automatically initializes on first call
 */
export async function getEmailService() {
  if (!emailServiceInstance) {
    emailServiceInstance = new EmailService();
    try {
      await emailServiceInstance.initialize();
    } catch (error) {
      logger.error('Failed to initialize email service:', error.message);
      // Don't throw - allow app to continue but email won't work
    }
  }
  return emailServiceInstance;
}

export default getEmailService;

/**
 * Render an English receipt email for customers matching verification email style.
 * Keeps colors neutral and supports light/dark via `color-scheme`.
 */
export function renderReceiptCustomerHTML({ order, logoUrl, frontendOrderUrl }) {
  const orderId = order.id || '';
  const date = order.created_at || new Date().toISOString();
  const customerName = (order.customer && order.customer.name) || '';
  const total = order.total_price || order.total || 0;

  return `
  <!doctype html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; margin:0; padding:0; }
      .wrapper { padding: 30px; background: #FAFAFA; }
      @media (prefers-color-scheme: dark) { .wrapper { background:#0B0B0B } }
      .container { max-width:600px; margin:0 auto; background:#fff; border-radius:6px; overflow:hidden; border:1px solid #EEE }
      @media (prefers-color-scheme: dark) { .container { background:#111; border-color:#222 } }
      .header { padding:28px; text-align:center; background:#111; }
      .wordmark { font-size:28px; font-weight:800; letter-spacing:6px; color:#fff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; }
      @media (prefers-color-scheme: dark) { .header { background:#fff; } .wordmark { color:#000; } }
      .content { padding:28px; color:#222 }
      @media (prefers-color-scheme: dark) { .content { color:#DDD } }
      .muted { color:#6B7280 }
      .button { display:inline-block; padding:12px 20px; background:#111; color:#fff; border-radius:8px; text-decoration:none }
      @media (prefers-color-scheme: dark) { .button { background:#fff; color:#000 } }
      .small { font-size:13px }
    </style>
  </head>
  <body>
    <div class="wrapper">
      <div class="container">
        <div class="header">
          <div class="wordmark">YSHOP</div>
        </div>
        <div class="content">
          <p class="small">Hello ${customerName || 'Customer'},</p>
          <h2 style="margin-top:6px">We've received your order</h2>
          <p class="muted small">Order <strong>#${orderId}</strong> • ${date}</p>

          <p style="margin-top:18px">Thank you for your purchase. Attached is a formal receipt (PDF) you can download and keep as proof of payment.</p>

          <!-- View Order button removed for customer emails; PDF is attached -->

          <hr style="margin:24px 0; border:none; border-top:1px solid #EEE" />

          <p class="small muted">If you didn't place this order, contact support immediately.</p>
        </div>
      </div>
    </div>
  </body>
  </html>
  `;
}

export function renderReceiptStoreHTML({ order, store, splits = {}, logoUrl }) {
  const orderId = order.id || '';
  const date = order.created_at || new Date().toISOString();
  const storeName = (store && store.name) || 'Store Owner';

  const platform = splits.platform ?? '—';
  const driver = splits.driver ?? '—';
  const storeAmount = splits.store ?? '—';

  return `
  <!doctype html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; margin:0; padding:0; }
      .wrapper { padding: 30px; background: #FAFAFA; }
      @media (prefers-color-scheme: dark) { .wrapper { background:#0B0B0B } }
      .container { max-width:600px; margin:0 auto; background:#fff; border-radius:6px; overflow:hidden; border:1px solid #EEE }
      @media (prefers-color-scheme: dark) { .container { background:#111; border-color:#222 } }
      .header { padding:28px; text-align:center; background:#111; }
      .wordmark { font-size:28px; font-weight:800; letter-spacing:6px; color:#fff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; }
      @media (prefers-color-scheme: dark) { .header { background:#fff; } .wordmark { color:#000; } }
      .content { padding:28px; color:#222 }
      @media (prefers-color-scheme: dark) { .content { color:#DDD } }
      table { width:100%; border-collapse:collapse; margin-top:12px }
      td, th { padding:8px; border-bottom:1px solid #F0F0F0; text-align:right }
      @media (prefers-color-scheme: dark) { td, th { border-bottom:1px solid #222 } }
      .muted { color:#6B7280 }
      .small { font-size:13px }
    </style>
  </head>
  <body>
    <div class="wrapper">
      <div class="container">
        <div class="header">
          <div class="wordmark">YSHOP</div>
        </div>
        <div class="content">
          <h2 style="margin:0 0 6px 0">New Order Received</h2>
          <p class="muted small">Order <strong>#${orderId}</strong> • ${date}</p>

          <p style="margin-top:12px">A new order has been placed. Below is the quick payout breakdown:</p>

          <table>
            <tr><td style="text-align:right">Platform (fee)</td><td style="text-align:left">${platform}</td></tr>
            <tr><td style="text-align:right">Driver</td><td style="text-align:left">${driver}</td></tr>
            <tr><td style="text-align:right">Store Net</td><td style="text-align:left">${storeAmount}</td></tr>
          </table>

          <p class="small muted" style="margin-top:12px">Attached is the full receipt (PDF) with order items and product images.</p>
        </div>
      </div>
    </div>
  </body>
  </html>
  `;
}
