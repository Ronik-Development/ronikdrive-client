import 'dart:convert';

import 'legal_documents_page.dart';

const _escape = HtmlEscape();
String _text(String value) => _escape.convert(value);

/// Generates public documents from exactly the same copy shown inside the app.
Map<String, String> renderLegalHtml() {
  final pages = <String, String>{};
  String frame(String title, String route, String content) =>
      '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_text(title)} | RonikCloud</title>
<link rel="canonical" href="https://ronikcloud.com$route">
<style>body{font:17px/1.65 system-ui,sans-serif;color:#19212d;background:#fff;margin:0}main,nav,footer{max-width:900px;margin:auto;padding:24px}a{color:#174b98}h1,h2{line-height:1.25}h2{margin-top:2em}li{margin-bottom:.7em}nav{border-bottom:1px solid #ccd3dd}footer{border-top:1px solid #ccd3dd}@media print{nav,footer{display:none}}</style>
<link rel="stylesheet" href="/site.css"></head><body class="document-page"><nav aria-label="Main navigation"><a href="/">RonikCloud</a> · <a href="/legal">Legal documents</a> · <a href="/support">Support</a></nav>
<main id="main"><h1>${_text(title)}</h1>$content</main>
<footer><a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/delete-account">Delete account</a><p>Legal version ${_text(LegalDocuments.legalVersion)}</p></footer></body></html>
''';
  for (final document in LegalDocuments.all) {
    final body = StringBuffer(
      '<p>Last updated: ${_text(document.lastUpdated)}</p><p>${_text(document.summary)}</p>',
    );
    for (final section in document.sections) {
      body.write('<section><h2>${_text(section.title)}</h2>');
      for (final paragraph in section.paragraphs) {
        body.write('<p>${_text(paragraph)}</p>');
      }
      if (section.bullets.isNotEmpty) {
        body.write('<ul>');
        for (final bullet in section.bullets) {
          body.write('<li>${_text(bullet)}</li>');
        }
        body.write('</ul>');
      }
      body.write('</section>');
    }
    pages['${document.route.substring(1)}.html'] = frame(
      document.title,
      document.route,
      body.toString(),
    );
  }
  pages['legal.html'] = frame(
    'Legal documents',
    '/legal',
    '<ul>${LegalDocuments.all.map((document) => '<li><a href="${document.route}">${_text(document.title)}</a> — ${_text(document.summary)}</li>').join()}</ul>',
  );
  return pages;
}
