with Q; use Q;

package body P is
   protected body PO1 is
      function Get_Content return Integer is (Content);

      procedure Set_Content (X : Integer) is
      begin
         Content := X;
      end Set_Content;

      procedure Swap_Content is
         Tmp : Integer := Content;
      begin
         Set_Content (PO2.Get_Content);
         PO2.Set_Content (Tmp);
      end Swap_Content;
   end PO1;
end P;
