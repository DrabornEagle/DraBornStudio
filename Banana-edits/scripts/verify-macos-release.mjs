import fs from 'node:fs';
import path from 'node:path';
import { verifyReleaseArtifacts } from './release-signatures.mjs';

// Read-only verification. It does not access Keychain, sign, upload or publish.
try {
 const directory=process.argv[2],architecture=process.argv[3];
 if(!directory||!['arm64','x64'].includes(architecture))throw new Error('Use: node scripts/verify-macos-release.mjs release-artifacts/<version> arm64|x64');
 const root=path.resolve(import.meta.dirname,'..');
 const record=JSON.parse(fs.readFileSync(path.join(directory,`verification-${architecture}.json`),'utf8'));
 const fields=['version','build','architecture','distribution','notarization','signatureVerified','privacyAuditPassed','archive','sourceCommit','archiveSha256','feedSha256'];
 const policy=(record.distribution==='community'&&record.notarization==='NotRequested')||(record.distribution==='notarized'&&record.notarization==='Accepted');
 if(Object.keys(record).length!==fields.length||fields.some(name=>!Object.hasOwn(record,name))||record.architecture!==architecture||record.version!==path.basename(path.resolve(directory))||!policy||record.signatureVerified!==true||record.privacyAuditPassed!==true||!/^[a-f0-9]{40}$/.test(record.sourceCommit))throw new Error('The release verification record is incomplete or invalid.');
 const report=verifyReleaseArtifacts({archivePath:path.join(directory,`Banana-edits-${record.version}-macos-${architecture}.zip`),feedPath:path.join(directory,`appcast-${architecture}.xml`),publicKey:fs.readFileSync(path.join(root,'desktop/macos/Resources/SparklePublicKey.txt'),'utf8').trim(),version:record.version,build:record.build,architecture,sourceCommit:record.sourceCommit});
 if(report.archive!==record.archive||report.archiveSha256!==record.archiveSha256||report.feedSha256!==record.feedSha256)throw new Error('The release files do not match their verification record.');
 console.log(JSON.stringify({...report,distribution:record.distribution,notarization:record.notarization},null,2));
} catch(error) {
 // Do not print file contents, private paths or untrusted metadata on failure.
 console.error(error.message?.startsWith('Use:')?error.message:'Mac release verification failed. No files were changed or published.');
 process.exitCode=1;
}
