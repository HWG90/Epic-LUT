// Exact, bounded, read-only animation resource lookup using the reviewed archive reader.
using System;
using System.IO;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;

public static class EpicAuthoredPreviewReader {
 const ulong Avatar = 0x4d1c334d294dfa97UL;
 const ulong UnitType = 0xe0a48d0be9a7453fUL;
 const ulong BonesType = 0x18dead01056b72e9UL;
 const ulong AnimationType = 0x931e336d7646cc26UL;
 const string OwnerArchive = "18235e0c9ec0e636";
 const int FileBudget = 16 * 1024 * 1024, SetBudget = 32 * 1024 * 1024;
 const long MetadataBudget = 512L * 1024 * 1024, RowBudget = 6000000;
 static readonly ulong[] Clips = {0x759c08277f1296d0UL, 0x070b422612518debUL,
                                0xe32b270524630569UL, 0x39250e5b6313a0b2UL};
 static readonly BindingFlags Hidden = BindingFlags.Instance | BindingFlags.NonPublic;
 static string Key(ulong name, ulong kind) {return name.ToString("x16")+"."+kind.ToString("x16")+".bin";}
 static uint U(byte[] bytes, int at) {
  if(at<0 || at>bytes.Length-4)throw new Exception("Authored resource integer bounds");
  return BitConverter.ToUInt32(bytes, at);
 }
 static ulong Q(byte[] bytes, int at) {
  if(at<0 || at>bytes.Length-8)throw new Exception("Authored resource offset bounds");
  return BitConverter.ToUInt64(bytes, at);
 }
 static void Check(string status, Stopwatch clock) {
  if(clock.Elapsed.TotalSeconds>180)throw new Exception("Authored animation lookup exceeded 180 seconds");
  if(File.Exists(status+".cancel"))throw new Exception("Authored animation extraction canceled");
 }
 static byte[] Read(EpicOriginalReader reader, MethodInfo method, string archive, ulong at, int size, string status, Stopwatch clock) {
  Check(status, clock);
  byte[] bytes;
  try {bytes=(byte[])method.Invoke(reader, new object[]{archive, at, size});}
  catch(TargetInvocationException error) {throw error.InnerException ?? error;}
  Check(status, clock);
  if(bytes==null || bytes.Length!=size)throw new Exception("Short authored animation resource");
  return bytes;
 }
 static void Atomic(string path, byte[] bytes) {
  // Entry script rejects symlink/junction destinations. OneDrive placeholders
  // also carry ReparsePoint and must remain usable in the canonical workspace.
  string temporary=path+"."+Guid.NewGuid().ToString("N")+".pending";
  try {
   using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
    stream.Write(bytes,0,bytes.Length);stream.Flush(true);
   }
   if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
  } finally {if(File.Exists(temporary))File.Delete(temporary);}
 }
 static void Validate(Dictionary<string,byte[]> bodies) {
  byte[] unit=bodies[Key(Avatar,UnitType)],bones=bodies[Key(Avatar,BonesType)];
  if(unit.Length<56 || Q(unit,8)!=Avatar)throw new Exception("Authored avatar references another skeleton");
  uint count=U(bones,0),lods=U(bones,4);
  if(count<1 || count>512 || lods>64 || 8L+lods*8L+count*4L>bones.Length)throw new Exception("Authored skeleton count bounds");
  foreach(ulong clip in Clips) {
   byte[] data=bodies[Key(clip,AnimationType)];
   if(data.Length<24 || U(data,4)!=count)throw new Exception("Authored clip skeleton count differs");
   float seconds=BitConverter.ToSingle(data,8);
   if(float.IsNaN(seconds) || float.IsInfinity(seconds) || seconds<=0 || seconds>600)throw new Exception("Authored clip duration bounds");
   if(U(data,12)>data.Length || U(data,16)>4096 || U(data,20)>4096)throw new Exception("Authored clip header bounds");
  }
 }
 public static int Run(string gameData, string destination, int ownerPID, string status) {
  string game=Path.GetFullPath(gameData).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
  string output=Path.GetFullPath(destination);
  if(output.StartsWith(game,StringComparison.OrdinalIgnoreCase))throw new Exception("Authored cache cannot be inside game data");
  if(!Directory.Exists(game) || !Directory.Exists(output))throw new Exception("Authored animation directories unavailable");
  var clock=Stopwatch.StartNew();
  var flags=BindingFlags.Static|BindingFlags.NonPublic;
  typeof(EpicOriginalReader).GetField("owner",flags).SetValue(null,ownerPID);
  typeof(EpicOriginalReader).GetField("progress",flags).SetValue(null,status);
  typeof(EpicOriginalReader).GetField("healthChecked",flags).SetValue(null,false);
  var wanted=new HashSet<string>{Key(Avatar,UnitType),Key(Avatar,BonesType)};
  foreach(ulong clip in Clips)wanted.Add(Key(clip,AnimationType));
  var bodies=new Dictionary<string,byte[]>();
  long metadata=0,rows=0;int visited=0,total=0;
  MethodInfo method=typeof(EpicOriginalReader).GetMethod("Read",Hidden);
  if(method==null)throw new Exception("Reviewed archive reader interface unavailable");
  using(var reader=new EpicOriginalReader(game)) {
   metadata=((byte[])typeof(EpicOriginalReader).GetField("data",Hidden).GetValue(reader)).Length;
   var entries=(IDictionary)typeof(EpicOriginalReader).GetField("entries",Hidden).GetValue(reader);
   var names=new List<string>();
   foreach(string name in entries.Keys) {
    ulong parsed;
    if(name.Length==16 && ulong.TryParse(name,NumberStyles.HexNumber,CultureInfo.InvariantCulture,out parsed))names.Add(name);
   }
   names.Sort(StringComparer.Ordinal);
   if(names.Remove(OwnerArchive))names.Insert(0,OwnerArchive);
   foreach(string archive in names) {
    Check(status,clock);
    File.WriteAllText(status,"Loading exact authored salute: "+bodies.Count+"/6 resources; "+visited+" TOCs, "+rows+" rows");
    byte[] header=Read(reader,method,archive,0,72,status,clock);metadata+=72;
    if(U(header,0)!=0xf0000011)continue;
    uint types=U(header,4),count=U(header,8);
    if(types>4096 || count>100000)throw new Exception("Authored lookup TOC count bounds");
    int at=checked(72+(int)types*32),size=checked(at+(int)count*80);
    if(metadata+size>MetadataBudget || rows+count>RowBudget)throw new Exception("Authored lookup metadata budget exceeded");
    byte[] toc=Read(reader,method,archive,0,size,status,clock);
    metadata+=size;rows+=count;visited++;
    for(int i=0;i<count;i++) {
     Check(status,clock);
     int p=at+i*80;string filename=Key(Q(toc,p),Q(toc,p+8));
     if(!wanted.Contains(filename) || bodies.ContainsKey(filename))continue;
     uint bytes=U(toc,p+56);
     if(bytes<1 || bytes>FileBudget || total+(long)bytes>SetBudget)throw new Exception("Authored resource byte budget exceeded");
     if(Q(toc,p+8)==AnimationType && (U(toc,p+60)!=0 || U(toc,p+64)!=0))throw new Exception("Authored animation uses an unsupported external stream");
     byte[] body=Read(reader,method,archive,Q(toc,p+16),(int)bytes,status,clock);
     bodies.Add(filename,body);total+=(int)bytes;
    }
    if(bodies.Count==wanted.Count)break;
   }
  }
  if(bodies.Count!=wanted.Count)throw new Exception("Exact authored salute resources missing: "+bodies.Count+"/6");
  Validate(bodies);
  foreach(string filename in wanted) {
   Check(status,clock);
   string path=Path.GetFullPath(Path.Combine(output,filename));
   if(!path.StartsWith(output.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Authored cache path leaves version folder");
   Atomic(path,bodies[filename]);
  }
  File.WriteAllText(status,"Authored salute ready: 6 resources, "+total+" bytes; "+visited+" TOCs");
  return bodies.Count;
 }
}
