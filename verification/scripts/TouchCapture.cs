// Read-only Raw Input subscription for this touchscreen only; never keyboard/mouse.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
public class TouchCapture : NativeWindow {
 [StructLayout(LayoutKind.Sequential)] struct RID { public ushort page,usage; public uint flags; public IntPtr target; }
 [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterRawInputDevices(RID[] d,uint n,uint size);
 [DllImport("user32.dll",SetLastError=true)] static extern uint GetRawInputData(IntPtr h,uint command,IntPtr data,ref uint size,uint header);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr h,uint command,StringBuilder data,ref uint size);
 StreamWriter file; Stopwatch clock=new Stopwatch(); int reports;
 TouchCapture(string path) {
  CreateHandle(new CreateParams { Caption="FPGA touch capture", Parent=new IntPtr(-3) });
  file=new StreamWriter(path,false,new UTF8Encoding(false));clock.Start();
  var rid=new RID {page=13,usage=4,flags=0x100,target=Handle};
  if(!RegisterRawInputDevices(new RID[]{rid},1,(uint)Marshal.SizeOf(typeof(RID))))throw new Exception("Raw Input registration failed");
 }
 protected override void WndProc(ref Message m) {
  if(m.Msg==0xff) {
   uint size=0,header=(uint)(IntPtr.Size==8?24:16);
   GetRawInputData(m.LParam,0x10000003,IntPtr.Zero,ref size,header);
   if(size>=header+8 && size<=65536) {
    IntPtr data=Marshal.AllocHGlobal((int)size);
    try {
     if(GetRawInputData(m.LParam,0x10000003,data,ref size,header)==size && Marshal.ReadInt32(data)==2) {
      IntPtr device=Marshal.ReadIntPtr(data,8);uint chars=1024;var name=new StringBuilder(1024);
      GetRawInputDeviceInfo(device,0x20000007,name,ref chars);
      if(name.ToString().IndexOf("VID_1A86&PID_E5E3",StringComparison.OrdinalIgnoreCase)>=0) {
       int length=Marshal.ReadInt32(data,(int)header),count=Marshal.ReadInt32(data,(int)header+4);
       if(length>0 && length<=64 && count>0 && (long)header+8+(long)length*count<=size) {
        byte[] bytes=new byte[length];
        for(int i=0;i<count;i++) {
         Marshal.Copy(IntPtr.Add(data,(int)header+8+i*length),bytes,0,length);
         string hex=BitConverter.ToString(bytes).Replace("-","");
         file.WriteLine("{\"elapsed_ms\":"+clock.ElapsedMilliseconds+",\"hex\":\""+hex+"\"}");reports++;
        }
        file.Flush();
       }
      }
     }
    } finally {Marshal.FreeHGlobal(data);}
   }
  }
  base.WndProc(ref m);
 }
 public static void Run(string path,int seconds) {
  var capture=new TouchCapture(path);var timer=new Timer();
  timer.Interval=seconds*1000;timer.Tick+=(s,e)=>Application.ExitThread();timer.Start();
  Console.WriteLine("READY: only touchscreen 1A86:E5E3, "+seconds+" seconds; no keyboard/mouse capture");
  try {Application.Run();} finally {
   timer.Stop();timer.Dispose();capture.file.Dispose();capture.DestroyHandle();
   Console.WriteLine("CAPTURED reports="+capture.reports);
  }
 }
}
