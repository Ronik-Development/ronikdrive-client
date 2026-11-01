import 'package:flutter/material.dart';

import '../shared/app_page_title.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last updated: ${document.lastUpdated}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        document.summary,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final section in document.sections) ...[
                _LegalSectionCard(section: section),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    ).withAppPageTitle('${document.title} | RonikCloud');
  }
}

class LegalDocumentsIndexPage extends StatelessWidget {
  const LegalDocumentsIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Legal Documents')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: [
              Text(
                'RonikCloud Legal Documents',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'These documents explain the terms, privacy practices, service limits, billing rules, retention windows, and subprocessors for RonikCloud.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              for (final document in LegalDocuments.all)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: Icon(document.icon),
                    title: Text(document.title),
                    subtitle: Text(document.summary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentPage(document: document),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ).withAppPageTitle('Legal Documents | RonikCloud');
  }
}

class _LegalSectionCard extends StatelessWidget {
  const _LegalSectionCard({required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final paragraph in section.paragraphs) ...[
              const SizedBox(height: 12),
              Text(
                paragraph,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ],
            if (section.bullets.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final bullet in section.bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: 5,
                          height: 5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bullet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.route,
    required this.title,
    required this.summary,
    required this.lastUpdated,
    required this.icon,
    required this.sections,
  });

  final String id;
  final String route;
  final String title;
  final String summary;
  final String lastUpdated;
  final IconData icon;
  final List<LegalSection> sections;
}

class LegalSection {
  const LegalSection({
    required this.title,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

class LegalDocuments {
  const LegalDocuments._();

  // Billing-retention and account-deletion changes are material and therefore
  // advance the version that signed-in users must accept.
  static const String legalVersion = '2026-09-10';
  static const String lastUpdated = 'September 10, 2026';
  static const String sharingPrivacyUpdated = 'October 16, 2026';
  static const String identityUpdated = 'July 15, 2026';
  static const String supportEmail = 'support@ronikcloud.com';
  static const String controllerIdentity =
      'Tomáš Názler, 24. dubna 145, Zeleice 664 43, Czech Republic';

  static const terms = LegalDocument(
    id: 'terms',
    route: '/terms',
    title: 'Terms of Service',
    summary:
        'The agreement for creating an account, using RonikCloud, storing files, and paying for a subscription.',
    lastUpdated: lastUpdated,
    icon: Icons.description_outlined,
    sections: [
      LegalSection(
        title: '1. Who These Terms Apply To',
        paragraphs: [
          'These Terms of Service govern access to RonikCloud, a cloud file storage and backup service operated by $controllerIdentity.',
          'By creating an account, starting checkout, or using the service, you agree to these terms and confirm that you are legally able to enter into this agreement.',
        ],
      ),
      LegalSection(
        title: '2. Accounts and Security',
        bullets: [
          'You must provide accurate account information and keep your email address current.',
          'You are responsible for protecting your password, devices, recovery information, and any second-factor credentials.',
          'Tell us promptly at support@ronikcloud.com if you believe your account has been accessed without permission.',
        ],
      ),
      LegalSection(
        title: '3. The Service',
        paragraphs: [
          'RonikCloud provides encrypted file storage, folder organization, downloads, offline access, and backup features. Some features may be beta, experimental, or platform-limited.',
          'We may change, suspend, or discontinue features when needed for security, reliability, legal compliance, or product improvement.',
        ],
      ),
      LegalSection(
        title: '4. Subscriptions and Payment',
        bullets: [
          'Paid plans renew automatically until canceled through the billing provider or another supported cancellation method. Checkout identifies the price, billing interval, renewal behavior, and provider before purchase.',
          'Stripe or the applicable app store collects payment credentials. RonikCloud never receives or stores a full card number or card security code. RonikCloud stores billing status, plan, invoice or transaction, customer, and subscription identifiers needed to operate and support the service.',
          'A Stripe auto-renewing subscription requires Stripe to retain a reusable payment credential while renewal remains enabled. If checkout is abandoned before confirmation, no RonikCloud subscription or charge is created. Stripe may still process the checkout session and payment input already entered under its privacy policy. If you do not want a reusable credential retained for RonikCloud renewal, do not confirm an auto-renewing checkout.',
          'Canceling renewal, deleting a RonikCloud account, and requesting a refund are separate actions. The Cancellation and Refund Policy explains the effect of each action and the provider-specific route.',
          'In the general release, the in-app account-closure control records an authenticated request authorizing permanent deletion. Submitting that request does not immediately sign the user out, end access, cancel billing, or delete data. Closure is processed in stages, with account access disabled before personal storage is erased. A separate support email is not required to confirm an authenticated request. We target completion within 28 days and provide a private status receipt. We aim to acknowledge account requests within two Czech business days. We respond to privacy-rights requests within one month. Where the law permits an extension of up to two further months, we explain the reasons within the first month. Identity or ownership checks and technical work do not remove these duties. Cancel renewal separately to stop a future renewal while a closure request is pending.',
          'Taxes, exchange rates, and payment-provider fees may vary by location and payment method.',
        ],
      ),
      LegalSection(
        title: '5. Files and Encryption',
        paragraphs: [
          'RonikCloud is designed so file content and protected file names are encrypted before storage. New protected folder labels are also encrypted on the device; legacy folder metadata is upgraded when you use the in-app protection action or edit an affected folder. Once a canonical encrypted label and its matching recovery metadata exist, bounded maintenance removes redundant readable name and path copies.',
          'Operational metadata such as size, upload timestamps, opaque file and folder references, parent-child relationships, access relationships, a coarse weekly storage-lifecycle boundary, storage-routing identifiers, encrypted-name fields, and billing state remains necessary to operate the service. Routine file access does not retain its action kind or a precise per-file access time. File records do not receive mirrored password-share state, counts, or exact last-share times; bounded maintenance removes legacy mirrors. Client-side encryption does not hide request timing, IP/connection data, traffic volume, or all account activity from service infrastructure.',
          'You are responsible for keeping local devices, passphrases, exported files, shared files, and backups under your control.',
          'By uploading, storing, or sharing a file, you represent and warrant that you own it or possess every permission, licence, and other right needed to store and share it through RonikCloud.',
        ],
      ),
      LegalSection(
        title: '6. Acceptable Use',
        paragraphs: [
          'You may not use RonikCloud for illegal content, malware, credential theft, harassment, abuse, intellectual-property infringement, privacy violations, platform attacks, spam, or attempts to bypass storage, billing, or security controls.',
        ],
      ),
      LegalSection(
        title: '7. Suspension and Termination',
        paragraphs: [
          'We may suspend or terminate access if required by law, if payment fails, if security risk is detected, or if these terms are violated. Account deletion and unpaid subscription retention are described in the Data Retention Policy.',
        ],
      ),
      LegalSection(
        title: '8. Disclaimers and Liability',
        paragraphs: [
          'The service is provided as-is and as-available to the extent allowed by law. We do not guarantee uninterrupted availability, loss-free storage, or compatibility with every device, provider, or network.',
          'Nothing in these Terms excludes or limits liability or a consumer remedy where doing so would be unlawful. Mandatory consumer rights continue to apply.',
        ],
      ),
      LegalSection(
        title: '9. Contact',
        paragraphs: [
          'Questions about these terms can be sent to support@ronikcloud.com.',
        ],
      ),
      LegalSection(
        title: '10. Consumer Rights and Complaints',
        paragraphs: [
          'Contact support@ronikcloud.com to report a service defect or make a complaint. Describe the problem and the remedy requested; do not send payment-card details, passwords or encryption keys. Mandatory rights to bring a digital service into conformity, receive a proportionate price reduction or terminate a contract remain available under applicable law.',
          'EU consumers generally have 14 days from concluding a distance service contract to withdraw. Our Cancellation and Refund Policy explains how to exercise this right. Ordinary cancellation of future renewal is a separate action.',
          'If a consumer dispute cannot be resolved directly, the Czech Trade Inspection Authority (Česká obchodní inspekce, ČOI) provides out-of-court consumer dispute resolution: https://coi.gov.cz/informace-o-adr/. This does not prevent you from pursuing a remedy before a competent court.',
          'These terms do not remove mandatory protections in your country of habitual residence or require you to bring consumer proceedings exclusively in the Czech Republic.',
        ],
      ),
    ],
  );

  static const privacy = LegalDocument(
    id: 'privacy',
    route: '/privacy',
    title: 'Privacy Policy',
    summary:
        'How RonikCloud processes account, billing, storage, support, security, and diagnostics data.',
    lastUpdated: sharingPrivacyUpdated,
    icon: Icons.privacy_tip_outlined,
    sections: [
      LegalSection(
        title: 'Optional website analytics and device storage',
        paragraphs: [
          'Essential browser and device storage supports authentication, encryption, security and your settings. The website also offers optional Google Analytics, disabled until you enable it using Privacy & cookies. Google Analytics can store _ga cookies and receive technical connection information. Our analytics configuration does not intentionally send account identifiers, file names, folder paths, query strings or URL fragments, and advertising personalization is disabled.',
          'Your optional analytics choice is stored on this browser for 180 days. You can accept, reject or customize it, and withdraw it later using Privacy & cookies. Withdrawal disables collection and removes accessible Google Analytics cookies on this site; it does not erase information already received by Google. This optional website integration does not add a Google Analytics SDK to native desktop or mobile apps. Optional website marketing-source measurement and its session storage follow this same consent choice. Essential service and security processing is separate.',
        ],
      ),
      LegalSection(
        title: '1. Scope and Controller',
        paragraphs: [
          'This Privacy Policy applies to RonikCloud accounts, apps, websites, billing, storage, backups, support, diagnostics, and security operations. The data controller is $controllerIdentity.',
        ],
      ),
      LegalSection(
        title: '2. Data We Process',
        bullets: [
          'Account data: Firebase Authentication processes the email address, display name, Firebase user ID, sign-in state, and security settings needed to authenticate the account. New general workspace-profile documents do not duplicate the email or display name. A bounded migration removes older duplicated names and removes older duplicated emails after any legacy email-derived storage identity has moved to an opaque identifier.',
          'Billing data: subscription tier, billing interval, Stripe customer and subscription IDs, app-store transaction identifiers, invoice or transaction metadata, payment status, and limited masked payment information that a provider may make available for billing support. RonikCloud never receives or stores a full card number or card security code. Stripe or the applicable app store handles payment credentials.',
          'Storage metadata: opaque object identifiers, encrypted file and folder labels for protected records, account-keyed backup integrity tags, file size, upload timestamps, opaque folder and parent references, access relationships, a coarse storage-lifecycle boundary shared by each UTC week, storage usage, and provisioning state. A successful open, preview, download, restore, or share sends only the opaque file ID; RonikCloud does not retain the action kind or a precise per-file access time. File records do not receive preview classifiers or mirrored password-share state, counts, or exact last-share times. Legacy precise access fields and those legacy mirrors are removed in bounded maintenance cycles. When a canonical encrypted label and matching recovery metadata are already present, bounded maintenance also removes redundant readable names and paths; a missing encrypted replacement must first be created by an authorized device. Business company/group records also hold bounded required and completed reconciliation counters so trusted devices can notice unfinished encrypted access changes; these counters contain no member, file, label, reason, or task details. Older records may retain legacy folder metadata or public content fingerprints until they are migrated or uploaded again.',
          'Password-share operational data: a random link token, owner and source-file identifiers needed for authorization, expiry and revocation state, encrypted-payload request budget and counter, one-bit first-access, near-budget, and blocked-proof alert states, and for new password-protected links a password-derived verifier that is not returned by the public metadata API. Short-lived failed-proof throttles use salted token and token/network hashes rather than raw link or network identifiers. Exact per-link access times are not retained. Filename and content type remain inside client-encrypted metadata. File-card badges are derived on the authorized device from the signed-in account’s own canonical links; another Business member does not receive that badge. Share account events have an operational event time but are generic and contain no recipient, filename, token, or source-file identifier. Older links may retain a readable private label until their policy is edited or they are revoked; bounded maintenance removes legacy precise access fields and file-level share mirrors.',
          'Optional-password links: files and their protected metadata stay encrypted in both modes. Password-free links carry a random share key in the private URL fragment, which is read by the recipient client and is not sent in the HTTP request. Anyone with the complete link can access the file subject to its current source access, expiry, revocation, and request limit. Entering a recipient email does not bind a bearer link to that mailbox.',
          'Requested share emails: for password-protected links, the recipient address and a token-only link pass through RonikCloud Functions and Resend to send the message you request. The email does not contain the file, filename, password, or decryption key. A server-only request receipt holds the owner, request and payload fingerprints, a keyed recipient hash, a link fingerprint, status, and bounded retry or lease state, with a seven-day expiry. It does not retain the raw recipient address or complete link. Short-lived counters limit email abuse. Provider acceptance does not guarantee mailbox delivery. Resend and recipient mail providers process the address and message under their own retention arrangements. For a password-free link, your selected email app receives the recipient and complete link locally; you press Send there. That email app and its mail providers can see the complete link and its share key. RonikCloud does not send that key through its email backend. Share passwords separately and send links only to intended recipients.',
          'Password-share source authorization and lifecycle privacy: every public metadata or download request rechecks that the source is active and, for Business files, that the creator still has active membership, source access, and share plus download permission. New expiry boundaries are rounded up to the next UTC hour, and new links retain no exact creation, revocation, update, or access timestamp. Current owner actions and bounded maintenance delete those timestamp fields from compatible older links. The encrypted derivative uses the creator\'s opaque Personal storage prefix so its object key does not encode company scope; server-only authorization still retains the creator and source identifiers required for those checks.',
          'File-request operational data: the owner relationship, random request and object identifiers, expiry, size and upload limits, counts, encrypted payload sizes, status, and timestamps needed to authorize and deliver submissions. New request titles and submitted filename/content-type metadata are client-encrypted. The public metadata API omits the owner identity and storage references, and direct public request-document reads are denied. Older readable request titles are replaced with a fixed generic value and older submitted content-type fields are removed in bounded maintenance cycles.',
          'Device and local data: encrypted offline vault objects, backup folder mappings, interrupted-transfer checkpoints, preferences, search settings, theme settings, and encryption salt. Backup mappings and fingerprints, transfer checkpoints, multipart upload IDs, and offline object/directory mappings are stored in an authenticated account-scoped encrypted cache using a key held by the operating system credential store. Offline file contents use chunked authenticated encryption bound to the environment, account, object, and file key; older readable offline copies are upgraded when their file key is available. Opening or sharing through another app creates a temporary decrypted copy that the operating system or receiving app may retain.',
          'Technical data: app version, platform, security and operational logs, user agent, referrer, IP-related security data, and support messages. Manual workspace reports remove common emails, paths, filenames, tokens, and secret-like values before sending, use an opaque Support code instead of copying the account email or raw user ID, and never attach a file, key, log, or automatic diagnostic. The remaining report text is readable by RonikCloud support. Automatic client diagnostics are off by default and are sent only after you enable Share minimal diagnostics in the Data safety center. New diagnostic reports contain only fixed error, reason, and library codes, platform, build mode, and fatal state; stored reports have no account ID or Support code and exclude exception messages and stacks, filenames, paths, workspace labels, URLs, and provider object references.',
          'Deleted-account suppression data: the long-lived server-only suppression record contains a one-way SHA-256 hash of the Firebase user ID, deletion state, and start/completion timestamps. Separately, a minimal profile tombstone and server-only rule-enforcement block remain at Firebase-user-ID-addressed document paths so already-issued sign-in tokens cannot recreate account data. Those enforcement records contain only deletion state, privacy version, timestamps, and expiry. Neither type contains an email, name, card detail, or file identifier; the long-lived record contains no raw user ID.',
          'Closure processing uses a separate server-only operation record with the account identifier, authenticated-request authorization version, phase, retry and lease state, and minimum verified provider references needed to resume safely. Optional manual approvals use hashed operator identifiers and approval times. It contains no file contents, passwords or encryption keys. After cleanup, provider references are removed and only a verified email may remain while completion notification is retried. The remaining operation is assigned a 90-day expiry even if notification fails. Unverified addresses use the private status receipt instead of email. Pending cleanup remains recorded until safely resolved.',
          'Account-closure request data: the authenticated in-app request queue is server-only and uses a SHA-256 hash of the Firebase user ID as its document key. Its minimal record contains the Firebase user ID needed for support operations, request status, privacy version, request/update timestamps, an internal response target, a hash of a private receipt token, fixed support-notification delivery status and code, notification timestamps and attempt count, and—after resolution—resolution timestamps and expiry. It contains no email copy, free-text reason, card detail, billing identifier, or file identifier.',
        ],
      ),
      LegalSection(
        title: '3. Why We Process Data',
        bullets: [
          'To create accounts, authenticate users, and provide encrypted file storage.',
          'To process subscriptions, enforce plan limits, and provide billing support.',
          'To protect accounts, investigate abuse, debug failures, and maintain service reliability.',
          'To match routine support and operational events using an opaque Support code instead of displaying a Firebase user ID or account email.',
          'To send service, security, billing, and product communications when permitted.',
        ],
      ),
      LegalSection(
        title: '4. Providers and Transfers',
        paragraphs: [
          'RonikCloud uses providers including Firebase/Google Cloud, Wasabi, Stripe, Resend for permitted product updates and necessary service, privacy, security, or support operational notifications, GitHub for release operations, and infrastructure providers needed to host or secure the service.',
          'Our production Firestore database is located in the United States multi-region (nam5), verified on 10 September 2026. Running Cloud Functions in Europe does not mean all account and file metadata stays in Europe. Ask support@ronikcloud.com for information about applicable transfer safeguards and how to obtain a copy. We do not promise EU-only storage.',
          'Providers may process data in more than one country. Stripe documentation requires merchants to disclose that payment data may be transferred, processed, and stored outside a customer location where applicable.',
        ],
      ),
      LegalSection(
        title: 'Legal Bases and Your Choices',
        bullets: [
          'Providing the contracted service: account authentication, encrypted storage, requested sharing, subscription administration and support needed to perform our agreement with you (GDPR Article 6(1)(b)). Necessary account and service data is required to provide those functions. A real recovery email is optional in username-only registration; choosing not to provide one limits email recovery and email contact.',
          'Legal obligations: records and disclosures necessary to comply with applicable accounting, tax and other legal requirements (Article 6(1)(c)). This does not justify keeping unrelated files or all account records indefinitely.',
          'Legitimate interests: proportionate security, fraud prevention, abuse handling, service reliability and establishing or defending legal claims (Article 6(1)(f)). You may object on grounds relating to your situation; processing must stop unless the applicable legal test for continuing is met.',
          'Consent: optional website analytics, optional client diagnostics and optional product-update communications (Article 6(1)(a), and applicable rules on device storage and electronic communications). You can withdraw using Privacy & cookies, the diagnostics setting, product-update preferences or an unsubscribe link, as applicable. Withdrawal does not affect earlier lawful processing or access to the core service.',
          'Where a Business customer determines the purposes of processing personal data in its workspace, it is responsible for that controller role. RonikCloud processes that customer content on documented instructions under the applicable data-processing agreement; our own account, billing and security responsibilities remain separate.',
        ],
      ),
      LegalSection(
        title: '5. Your Rights',
        paragraphs: [
          'Depending on your location, you may have rights to access, correct, delete, export, restrict, or object to processing of personal data. Where GDPR applies, we respond without undue delay and within one month of receiving a request. If its complexity or number permits an extension, we notify you within the first month with the reasons; the extension cannot exceed two further months. Requests are normally free of charge.',
          'Send privacy requests to support@ronikcloud.com. We may need to verify your identity before acting on a request.',
          'You can complain to a data-protection supervisory authority, particularly in your country of habitual residence, place of work or the alleged infringement. In the Czech Republic, contact the Úřad pro ochranu osobních údajů at https://uoou.gov.cz/. You do not have to complain to us first, and judicial remedies remain available.',
          'You may object to direct marketing at any time, free of charge. Where consent is the legal basis, you may withdraw it at any time. If a request is refused, we explain the reason and your complaint and judicial-remedy options within the applicable deadline.',
        ],
      ),
      LegalSection(
        title: '6. Retention and Deletion',
        paragraphs: [
          'Retention rules are described in the Data Retention Policy. A pending account-closure request remains until automated processing or support resolves it; it has no automatic expiry because deleting an unhandled request could defeat the user\'s request. After audited resolution, the request record is assigned an expiry 90 days after resolution. Scheduled maintenance may remove it after that expiry time. Completing account closure requests deletion of linked Stripe customer profiles and their reusable payment details. App-store payment credentials remain controlled by the store account. Some transaction records, logs, invoices, fraud records, provider backups, organization-owned workspace data, or records required for accounting, security, dispute resolution, or legal compliance may remain for a limited period after account deletion. After deletion succeeds, the pseudonymous long-lived deletion guard is assigned an expiry 400 days after completion solely to suppress delayed billing activity. The minimal Firebase-user-ID-addressed profile and rule-enforcement tombstones are assigned a 48-hour expiry. If closure is incomplete and authentication remains, closing-state deletion and enforcement records remain until the user retries or support safely resolves the deletion; removing them sooner could allow already-issued sign-in tokens to recreate data. Scheduled maintenance removes completed-deletion records after expiry, and a delayed maintenance run may complete removal after the expiry time.',
        ],
      ),
      LegalSection(
        title: '7. Contact',
        paragraphs: [
          'Privacy questions or requests can be sent to support@ronikcloud.com or by post to $controllerIdentity.',
        ],
      ),
    ],
  );

  static const acceptableUse = LegalDocument(
    id: 'acceptable_use',
    route: '/acceptable-use',
    title: 'Acceptable Use Policy',
    summary:
        'Rules for content, security, abuse prevention, and fair use of RonikCloud.',
    lastUpdated: lastUpdated,
    icon: Icons.verified_user_outlined,
    sections: [
      LegalSection(
        title: '1. Prohibited Content and Conduct',
        bullets: [
          'Do not store, share, or distribute illegal material, malware, stolen data, exploit kits, phishing content, spam, or content that violates rights of others.',
          'Do not harass, threaten, impersonate, dox, or facilitate abuse against another person or organization.',
          'Do not use the service to violate privacy, intellectual property, export, sanctions, or child-safety laws.',
        ],
      ),
      LegalSection(
        title: '2. Platform Integrity',
        bullets: [
          'Do not attack, scan, overload, reverse engineer, bypass limits, scrape, or interfere with RonikCloud, Firebase, Wasabi, Stripe, or connected infrastructure.',
          'Do not share credentials, abuse trials or promotions, evade payment, or attempt to access another user account or workspace.',
        ],
      ),
      LegalSection(
        title: '3. Enforcement',
        paragraphs: [
          'We may remove access, suspend accounts, preserve records, or report activity when needed for security, law, provider policy, or user protection.',
        ],
      ),
      LegalSection(
        title: '4. Reporting Illegal Content and Challenging Restrictions',
        paragraphs: [
          'Send notices of suspected illegal content to support@ronikcloud.com with the subject Illegal content notice. Include the exact share link or other location, why you believe the material is illegal, relevant facts, and a statement that the information is accurate and complete to the best of your knowledge. Include a contact email unless an applicable legal exception allows an anonymous notice. Do not include passwords, encryption keys or copies of suspected illegal material.',
          'We assess sufficiently precise notices diligently and inform the notifier of the decision when contact details are available. Where required, an affected user receives the reasons for an access restriction and available redress. Do not submit knowingly false or abusive notices.',
          'To challenge a restriction, contact support with the decision reference and an explanation. The review must consider your explanation; applicable legal complaint and court rights remain available. This contact also serves as the electronic contact point for users and competent authorities; English and Czech are accepted.',
        ],
      ),
    ],
  );

  static const cancellationRefund = LegalDocument(
    id: 'cancellation_refund',
    route: '/cancellation-refund',
    title: 'Cancellation and Refund Policy',
    summary:
        'How subscription renewal, cancellation, failed payment, and refund requests are handled.',
    lastUpdated: lastUpdated,
    icon: Icons.credit_card_off_outlined,
    sections: [
      LegalSection(
        title: '1. Subscriptions',
        paragraphs: [
          'RonikCloud subscriptions renew automatically until canceled. Renewal timing, price, billing interval, plan capacity, and billing provider are shown during checkout or account billing flows.',
          'For Stripe subscriptions, Stripe retains a reusable payment credential so it can collect later renewals. RonikCloud never receives or stores the full card number or card security code. If checkout is abandoned before confirmation, no RonikCloud subscription or charge is created, but Stripe may still process the checkout session and payment input already entered under its privacy policy. A non-renewing Stripe plan is not currently offered.',
        ],
      ),
      LegalSection(
        title: '2. Cancellation',
        paragraphs: [
          'You can cancel through the subscription management flow in the app where available, through the original app store, or by contacting support@ronikcloud.com from the account email. Cancellation stops future renewals but does not automatically delete the account, stored files, or an already completed charge.',
          'A Stripe cancellation normally keeps paid access through the stated current period. Apple subscriptions must be canceled in Apple subscription settings. Deleting a RonikCloud account does not cancel an Apple subscription or remove payment details from an Apple Account.',
        ],
      ),
      LegalSection(
        title: '3. Closing an Account',
        paragraphs: [
          'Permanent account closure and subscription cancellation are different actions. In the general release, Settings records an authenticated instruction for permanent account deletion. Submitting it does not immediately sign the user out, end access, cancel billing, or delete data. The automatic workflow verifies ownership, disables access before removing personal data, and provides a private status receipt. No separate support email is required to confirm the authenticated instruction. We target completion within 28 days. We aim to acknowledge account requests within two Czech business days. We respond to privacy-rights requests within one month. Where the law permits an extension of up to two further months, we explain the reasons within the first month. Identity or ownership checks and technical work do not remove these duties. Cancel renewal separately if you want to stop a future charge while the request is pending.',
          'When a verified closure is completed, RonikCloud access ends, the account and personal stored files are removed, a linked Stripe subscription is canceled without automatic proration or refund, and deletion of every verified linked Stripe customer profile and its reusable payment details is requested. Transaction and invoice records may remain where the payment provider or law requires them.',
          'Organization-owned workspace records may remain with the organization after membership is removed. A company owner cannot be closed until ownership is transferred or the company workspace is closed; contact support for the available next step if those controls are unavailable.',
          'Account deletion does not automatically issue a refund. Request a refund before deleting when possible so support can verify the account and charge more easily. A valid statutory claim can still be submitted afterward, subject to identity and transaction verification.',
          'For subscriptions purchased through Apple or another app store, cancel renewal and request any refund through that store. RonikCloud cannot delete payment credentials held in a user\'s store account.',
        ],
      ),
      LegalSection(
        title: '4. Refunds',
        paragraphs: [
          'Refund requests are reviewed case by case unless a mandatory consumer right applies. We may consider duplicate charges, accidental renewal, service unavailability, or billing errors. Nothing in this policy limits a mandatory consumer right.',
          'For Stripe charges, send the account email, approximate charge date, amount, and reason to support@ronikcloud.com, but never send a card number or security code. Approved refunds are sent through Stripe to the original payment method where supported. Apple and other app-store refunds are requested and decided through the applicable store.',
        ],
      ),
      LegalSection(
        title: 'Consumer Withdrawal from a New Service Contract',
        paragraphs: [
          'If you are an EU consumer, you can withdraw from a newly concluded distance service contract within 14 days without giving a reason. To exercise this right, send an unambiguous withdrawal statement to support@ronikcloud.com or by post to $controllerIdentity before the period expires. You may use the model wording below, but it is not compulsory.',
          'Model withdrawal statement: To RonikCloud, $controllerIdentity, support@ronikcloud.com. I give notice that I withdraw from my contract for the following service: [plan or service]. Contract concluded on: [date]. Consumer name: [name]. Consumer address: [address]. Account or order reference: [reference]. Date: [date]. Signature: [only if submitted on paper].',
          'For a qualifying withdrawal from a new RonikCloud service contract, we refund payments due under the withdrawal right within 14 days after receiving your notice, using the original payment method unless another method is expressly agreed without a fee. RonikCloud does not deduct a charge for ordinary storage-service use within this initial withdrawal period. This policy does not treat starting a continuing cloud service as a blanket waiver of withdrawal rights.',
          'For an Apple or other app-store purchase, the payment-provider refund route may be needed to return the payment. Contact us if you need help exercising a statutory right; the store route does not remove mandatory rights. Withdrawal can end the affected paid service. Request an export before account deletion if you want to retain your files; withdrawal alone does not instruct us to erase your account.',
          'A renewal is not automatically a new initial withdrawal period. This does not limit any additional right that applicable law or the billing provider gives you.',
        ],
      ),
      LegalSection(
        title: '5. Payment-Method Retention',
        paragraphs: [
          'An auto-renewing subscription cannot operate without a reusable payment credential at its billing provider. RonikCloud does not copy that credential into its own database. Stripe customers can manage billing through the Stripe-hosted portal. When a RonikCloud account is permanently deleted, RonikCloud requests deletion of its verified linked Stripe customer profiles and reusable payment details.',
          'Removing a reusable payment method does not erase transaction, refund, invoice, tax, fraud-prevention, or accounting records that the provider or RonikCloud must retain.',
        ],
      ),
      LegalSection(
        title: '6. Failed Payment and Retention',
        paragraphs: [
          'If payment fails or a subscription lapses, access may be limited and stored data may become eligible for deletion after the retention period described in the Data Retention Policy.',
        ],
      ),
    ],
  );

  static const dataRetention = LegalDocument(
    id: 'data_retention',
    route: '/data-retention',
    title: 'Data Retention Policy',
    summary:
        'How long account, billing, storage, diagnostics, and deleted-account data are retained.',
    lastUpdated: lastUpdated,
    icon: Icons.history_toggle_off_outlined,
    sections: [
      LegalSection(
        title: '1. Active Accounts',
        paragraphs: [
          'We retain account, billing, security, and storage metadata while your account is active and as needed to provide the service, resolve disputes, comply with law, and protect users.',
          'Submitting the authenticated in-app closure request does not immediately change sign-in, access, billing, or stored data. Its server-only queue record uses a SHA-256 hash of the Firebase user ID as the document key and contains the operational Firebase user ID, status, privacy version, request/update timestamps, fixed support-notification delivery status and code, notification timestamps and attempt count, and resolution fields when handled. It contains no email copy, free-text reason, card detail, billing identifier, or file identifier. A pending request has no automatic expiry and remains until automated processing or support resolves it. After audited resolution, it is assigned an expiry 90 days after resolution; scheduled maintenance may remove it later.',
        ],
      ),
      LegalSection(
        title: '2. Deleted Accounts',
        paragraphs: [
          'When a verified account closure is completed, RonikCloud attempts to remove app account records, storage credentials, personal stored file objects, and every verified linked Stripe customer profile with its reusable payment details. Organization-owned workspace records may remain with the organization after membership is removed. App-store payment credentials remain controlled by the store account. Some provider logs, transaction and invoice records, security records, backups, and audit records may remain where required or allowed by law.',
          'To prevent delayed Stripe activity from recreating a deleted account, RonikCloud retains a long-lived suppression record containing only a SHA-256 hash of the Firebase user ID, deletion state, and deletion timestamps. It contains no email, card detail, file identifier, or raw user ID. After deletion succeeds, it is assigned an expiry 400 days after completion.',
          'To block writes made with an already-issued sign-in token, RonikCloud also keeps a minimal profile tombstone and server-only rule-enforcement block at Firebase-user-ID-addressed document paths. They contain only deletion state, privacy version, timestamps, and expiry. After deletion completes, those records are assigned a 48-hour expiry. If closure is incomplete and authentication remains, closing-state deletion and enforcement records remain until the user retries or support safely resolves the deletion; removing them sooner could reopen account writes. Scheduled maintenance removes completed-deletion records after expiry, and a delayed maintenance run may complete removal after the expiry time.',
        ],
      ),
      LegalSection(
        title: '3. Subscription Lapse',
        paragraphs: [
          'If a paid subscription is not renewed, account access and stored data may be scheduled for permanent deletion after the in-app retention notice period, currently designed around a three-month lapse window unless changed by policy, law, or support action.',
        ],
      ),
      LegalSection(
        title: '4. Backups and Logs',
        paragraphs: [
          'Firestore metadata has point-in-time recovery enabled from 16 September 2026, retaining historical metadata for up to seven days. File-storage versioning preserves prior versions of subsequent writes; a finite version-expiry policy is still being established. Verified account closure removes the discoverable personal object versions. Recovery procedures must reapply completed deletions before restoring customer access.',
          'Provider backups, security logs, diagnostic events, and audit records may have separate retention windows. We keep these only as long as needed for security, reliability, accounting, legal compliance, and abuse prevention.',
          'Completion confirms removal from active service systems and the provider inventories available to us. It does not mean that every provider-internal backup is physically overwritten at that instant. Google Cloud publishes an internal deletion period of up to 180 days after a customer deletion instruction under its processing terms, subject to legal retention. Such residual copies are outside normal account access; they are not used to reopen your account.',
          'Opt-in client error reports expire 30 days after receipt and are removed by a daily cleanup process, unless a longer period is required for an active security investigation or legal obligation.',
          'Manual workspace support reports expire no later than 90 days after receipt. Legacy reports are migrated without extending 90 days from their original creation time; already expired or unsafe legacy records are deleted.',
        ],
      ),
    ],
  );

  static const subprocessors = LegalDocument(
    id: 'subprocessors',
    route: '/subprocessors',
    title: 'Subprocessors',
    summary: 'Infrastructure and service providers used to run RonikCloud.',
    lastUpdated: sharingPrivacyUpdated,
    icon: Icons.account_tree_outlined,
    sections: [
      LegalSection(
        title: 'Current Subprocessors',
        bullets: [
          'Google Firebase and Google Cloud: authentication, Firestore metadata, Cloud Functions, hosting, logging, and related backend infrastructure.',
          'Wasabi Technologies: encrypted object storage and related storage operations.',
          'Stripe: checkout, subscription billing, payment processing, invoice, tax, and customer billing records.',
          'Resend: permitted product updates, user-requested password-protected share-link emails, and necessary service, privacy, security, or support operational notifications. Share emails contain the selected recipient address and a token-only link, without a file, filename, password, or decryption key. The account-closure support alert contains only an opaque closure-request code and request timestamp, not a raw Firebase user ID, account email, or request text.',
          'GitHub: source control, CI/CD, release automation, and operational artifacts.',
          'Cloudflare: experimental Worker/R2 paths and edge/security infrastructure where configured.',
        ],
      ),
      LegalSection(
        title: 'Changes',
        paragraphs: [
          'We may add, replace, or remove subprocessors as the service changes. Material changes should be reflected in this page or account communications before production launch requirements require a stricter notice workflow.',
        ],
      ),
    ],
  );

  static const all = <LegalDocument>[
    terms,
    privacy,
    acceptableUse,
    cancellationRefund,
    dataRetention,
    subprocessors,
  ];

  static LegalDocument? byRoute(String route) {
    final trimmed = route.trim().toLowerCase();
    final normalized = trimmed.length > 1 && trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (normalized == '/privacy.html') {
      return privacy;
    }
    for (final document in all) {
      if (document.route == normalized) {
        return document;
      }
    }
    return null;
  }

  static LegalDocument? byId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final document in all) {
      if (document.id == normalized) {
        return document;
      }
    }
    return null;
  }
}

