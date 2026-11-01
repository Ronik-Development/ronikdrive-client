import 'dart:io';

void main() {
  final file = File('lib/src/home/workspace_home_page.dart');
  final lines = file.readAsLinesSync();
  
  int braceCount = 0;
  int lineNum = 0;
  bool classOpen = false;
  
  for (final line in lines) {
    lineNum++;
    if (line.contains('class _WorkspaceHomePageState')) classOpen = true;
    
    for (int i = 0; i < line.length; i++) {
      if (line[i] == '{') braceCount++;
      if (line[i] == '}') {
        braceCount--;
        if (classOpen && braceCount == 0) {
           // ignore: avoid_print
           print('Class potentially closed at line $lineNum');
           classOpen = false;
        }
      }
    }
  }
}