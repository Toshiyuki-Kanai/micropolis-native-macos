// SPDX-License-Identifier: GPL-3.0-or-later
// Test harness only; invokes the unmodified official v2.0.0 Java engine.
import micropolisj.engine.*;
import java.io.*;
import java.nio.file.*;
public final class JavaSaveCompatibility {
 public static void main(String[] args) throws Exception {
  File file=new File(args[0]);byte[] bytes=Files.readAllBytes(file.toPath());
  if(bytes.length!=27120) throw new AssertionError("classic size");
  Micropolis city=new Micropolis();city.load(file); // Actual File loader, not the bypass stream path.
  int mismatches=0;
  for(int x=0;x<120;x++) for(int y=0;y<100;y++) {
   int offset=3120+2*(x*100+y);
   int id=(((bytes[offset]&255)<<8)|(bytes[offset+1]&255))&1023;
   if(city.getTile(x,y)!=id) mismatches++;
  }
  if(mismatches!=0) throw new AssertionError("tile IDs changed: "+mismatches);
  if(city.gameLevel!=2 || city.cityTax!=9 || city.autoBulldoze) throw new AssertionError("options");
  city.save(new File(args[1]));
  Micropolis restored=new Micropolis();restored.load(new File(args[1]));
  if(restored.cityTime!=city.cityTime || restored.budget.totalFunds!=city.budget.totalFunds) throw new AssertionError("funds/time");
  System.out.println("PASS official MicropolisJ v2.0.0 File loader: 12000 tile IDs, difficulty/tax/bulldoze, funds/time, Java resave");
 }
}
