procedure Hard_Stuff (X : in out Float)
  with SPARK_Mode
is
begin
   if (for some Y in 0 .. 100_000 => X = (Float(Y) / 100_000.0) * (Float(Y) / 100_000.0)) then
      pragma Assert (X in 0.0 .. 1.0);
   end if;

   declare
      Copy : constant Float := X with Ghost;
   begin
      if X in 0.0 .. 1.0 then
         X := X - X * X;
         pragma Assert (X in 0.0 .. Copy);
      end if;
   end;
end Hard_Stuff;
