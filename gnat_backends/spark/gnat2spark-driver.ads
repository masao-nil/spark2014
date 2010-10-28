------------------------------------------------------------------------------
--                                                                          --
--                           GNAT2SPARK COMPONENTS                          --
--                                                                          --
--                    G N A T 2 S P A R K - D R I V E R                     --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                       Copyright (C) 2010, AdaCore                        --
--                                                                          --
-- gnat2spark is  free  software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software Foundation;  either version  2,  or  (at your option) any later --
-- version. gnat2spark is distributed in the hope that it will  be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHAN-  --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License  for more details. You  should  have  received a copy of the GNU --
-- General Public License  distributed with GNAT; see file COPYING. If not, --
-- write to the Free Software Foundation,  51 Franklin Street, Fifth Floor, --
-- Boston,                                                                  --
--                                                                          --
-- gnat2spark is maintained by AdaCore (http://www.adacore.com)             --
--                                                                          --
------------------------------------------------------------------------------
--  This package is the main driver for the Gnat2SPARK translation. It is
--  invoked by the gnat1 driver.

with Types;  use Types;

package Gnat2SPARK.Driver is

   procedure GNAT_To_SPARK (GNAT_Root : Node_Id);
   --  Translates an entire GNAT tree for a compilation unit into
   --  a set of SPARK sources. This is the main driver for the
   --  Ada-to-SPARK back end and is invoked by Gnat1drv.

   function Is_Back_End_Switch (Switch : String) return Boolean;
   --  Returns True if and only if Switch denotes a back-end switch

end Gnat2SPARK.Driver;
