import nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';
import { serviceUnavailable } from '../errors.js';

export interface OutboundMail {
  to: string;
  subject: string;
  text: string;
}

export interface Mailer {
  /** False means no SMTP is configured; callers must not claim mail was sent. */
  readonly configured: boolean;
  send(mail: OutboundMail): Promise<void>;
}

export function createMailer(options: { smtpUrl?: string; from: string }): Mailer {
  if (!options.smtpUrl) {
    return {
      configured: false,
      async send() {
        throw serviceUnavailable(
          'email_delivery_unconfigured',
          'Email delivery is not configured on this server, so no message was sent.',
        );
      },
    };
  }

  const transport: Transporter = nodemailer.createTransport(options.smtpUrl);
  return {
    configured: true,
    async send(mail) {
      await transport.sendMail({ from: options.from, ...mail });
    },
  };
}
