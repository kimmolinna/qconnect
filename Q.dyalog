﻿:Class Q
⍝ Interface from Dyalog APL to Q
⍝ Currently asssumes existence of #.DRC

    ⎕ML←1 ⋄ ⎕IO←0

    :Field Public CLT←''         ⍝ Public for debugging
    :Field Private LittleEndian

    cols←{(((⍴⍵)÷⍺),⍺)⍴⍵} ⍝ 4 cols ⍵ reshapes to have 4 cols
    fromsym←{z←¯1⌽⍵ ⋄ 1↓¨(z=⎕UCS 0)⊂z}
    To64Int←{{⎕ml←3⋄(∊8⍴⊂(8⍴1),0){{1⊃⍵:-2⊥~⍵⋄2⊥⍵}∊⌽⍺⊂⍺\⍵}⍵}11 ⎕DR ⍵}
    ToReal←{{(sign ⍵)×(exp ⍵)×(frac ⍵)}{⎕ML←3 ⋄ (∊4⍴⊂(8⍴1),0){∊⌽⍺⊂⍺\⍵}⍵}11 ⎕DR ⍵}
    frac←{⎕io←1⋄1++/{2*⍵}¨-(9↓⍵)/⍳23}
    exp←{2*127-⍨+/2*(⌽8↑1↓⍵)/⍳8}
    sign←{¯1*1↑⍵}            
    split←{a←⍺⋄''{0=⍴⍵:⍺ ⋄ ⍺,(⊂a↑⍵)∇(a↓⍵)}⍵}

    ∇ r←Int32Bytes x;int32;ok
      :Access Public
    ⍝ Return bytes representing x as an Int32
      (int32 ok)←((⎕DR x),323)⎕DR x
      ⎕SIGNAL ok↓11
      r←83 ⎕DR int32
    ∇

    ∇ r←SendWait data;z;done;length
      :If 0≠0⊃z←#.DRC.Send CLT data
          ('Send failed: ',,⍕z)⎕SIGNAL 11
      :EndIf
     
      r←⍬ ⋄ done←0 ⋄ length←¯1
      :Repeat
          :If 0=0⊃z←#.DRC.Wait CLT
              data←3⊃z
              :If length=¯1 ⍝ First block
                  length←256⊥⌽⍣(LittleEndian=⊃data)⊢4↓8↑data
                  r←data
              :Else
                  r,←data
              :EndIf
              done←length≤⍴r
          :Else
              ∘ ⍝ Transfer failed
          :EndIf
      :Until done
    ∇

    ∇ r←x expr;data;z
      :Access Public
      data←apl2q expr
      r←SendWait data
      :If LittleEndian≠⊃r ⋄ ∘ ⋄ :EndIf ⍝ Can't deal with other-endian architecture
      :If 128=⊃BUFFER←8↓r ⍝ Error?
          (⎕UCS 1↓BUFFER)⎕SIGNAL 11
      :Else
          r←q2apl ⍬
      :EndIf
    ∇

    ∇ r←apl2q x;head;⎕IO;data;length
      :Access Public
    ⍝ Implemen Q -8! serialization
     
      head←4⍴0
      head[0]←LittleEndian
      head[1]←1 ⍝ [1] 0=asynch, 1=synch, 2=response from Q
    ⍝ [2 3] = 0 unused
     
    ⍝ Data:
    ⍝ [0] = Type http://code.kx.com/wiki/Reference/Datatypes
    ⍝ [1] = Attributes (1=sorted+2=Unique+4=Parted+8=Grouped)
    ⍝ [2-5] = Element count
    ⍝ [6-] = Data
     
      :Select ⎕DR x
      :Case 80
          data←10 0,(Int32Bytes⍴,x),⎕UCS x
      :Else
          'Unsupported type'⎕SIGNAL 11
      :EndSelect
     
      length←Int32Bytes 8+⍴data ⍝ [4-7] = Int32 overall length
      r←(head,length),data
    ∇

    ∇ r←qcutlist r;x;m;offset;type;n
    ⍝ Cut a Q list into a piece per element
     
      m←(⍴x←r)⍴0
      offset←0
     
      :Repeat
          :Select type←⊃x
          :Case 245 ⋄ n←1+x⍳0 ⍝ Scalar symbol
          :Case 7 ⋄ shape←256⊥(⌽⍣LittleEndian)2↓6↑x
              n←6+8×shape
          :Case 0
              'Doubly nested list encountered'⎕SIGNAL 11
          :Else
              ∘
          :EndSelect
          m[offset]←1
          offset+←n
          x←n↓x
      :Until 0=⍴x
      r←m⊂r
    ∇

    ∇ r←q2apl dummy;type;flags;shape;n;atom;error;list;result;headsize;length;size;extrabyte;t;names;a
      :Access Public
    ⍝ Implement Q -9! deserialization to Dyalog APL
     
      type←⊃BUFFER
      error←type=128
      atom←type>236
      :If (type≥100)∧type≤112 ⋄ r←'Function type: ',⍕type ⋄ →0 ⋄ :EndIf
     
      :If error∨atom
          type←256-type
          headsize←shape←1
      :Else
          list←type=0
          flags←2⊃BUFFER
          headsize←6+type=99
          shape←256⊥(⌽⍣LittleEndian)¯4↑headsize↑BUFFER
      :EndIf
     
      :Select type
      :Case 0 ⍝ List
          BUFFER←headsize↓BUFFER
          r←q2apl¨⍳shape
     
      :Case 99 ⍝ Dict
          :If 98=1⊃BUFFER ⍝ key table
              BUFFER←1↓BUFFER
              r←q2apl¨0 0
              r←⊃,/r
          :Else
              BUFFER←headsize↓BUFFER
              length←1+(+\0=BUFFER)⍳shape ⍝ Look for shape'th null terminator
              names←fromsym ⎕UCS length↑BUFFER
              BUFFER←length↓BUFFER        ⍝ Drop names from buffer
              :If shape=⍴names ⍝ That looks right
              :AndIf 0=⊃BUFFER ⍝ First thing in BUFFER is a list
              :AndIf shape=⍴r←q2apl 0 ⍝ And it has the right length
                  r←names⍪↑[¯0.5]r
              :Else
                  ∘ ⍝ Unable to decipher dictionary
              :EndIf
          :EndIf
     
      :Case 98 ⍝ Table ("flipped" dictionary)
          :If 99=2⊃BUFFER ⍝ Should be a dictionary inside
              BUFFER←2↓BUFFER
              r←q2apl 0   ⍝ Just decipher that
          :Else
              ∘ ⍝ Unable to decipher table
          :EndIf
      :Case 128 ⍝ Error
          (⎕UCS 1↓BUFFER)⎕SIGNAL 11
      :Else
     
          size←type⊃0 1 16 0 1 2 4 8 4 8 1 ¯1 8 4 4 8 8 4 4 4
     
          :If error∨atom∧type=11 ⋄ length←1+(headsize↓BUFFER)⍳0
          :ElseIf type=11 ⍝ symbol vector
              length←1+(+\0=headsize↓BUFFER)⍳shape
          :Else ⋄ length←size×shape
          :EndIf
     
          r←⎕UCS headsize↓(n←length+headsize)↑BUFFER

          BUFFER←n↓BUFFER
     
          :Select type
          :Case 1 ⋄ r←⎕UCS r ⍝ Boolean
          :Case 2 ⋄ ∘ ⍝ GUID (no-op)
          :Case 4 ⋄ ∘ ⍝ Byte (no-op)
          :Case 5 ⋄ r←163 ⎕DR r ⍝ Int16
          :Case 6 ⋄ r←323 ⎕DR r ⍝ Int32
          :Case 7 ⋄ r←To64Int¨8 split r ⍝ Int64
          :Case 8 ⋄ r←ToReal¨4 split r ⍝ real
          :Case 9 ⋄ r←645 ⎕DR r ⍝ double    
          :Case 10 ⍝ Char (no-op)
          :Case 11 ⋄ r←fromsym r ⍝ Symbols
          :Case 12 ⋄ r←10 ¯3 ⎕dt To64Int¨8 split r ⍝ Timestamp
          :Case 13 ⋄ r←{{(⌊⍵÷12),1+12|⍵}24000+⍵}¨323 ⎕DR r ⍝ Month
          :Case 14 ⋄ r←{3↑2 ⎕NQ'.' 'IDNToDate' (36525+⍵)}¨323 ⎕DR r ⍝ Date
          :Case 15 ⋄ r←{∊13 ¯1 ⎕dt 10957 + ⍵}¨645 ⎕dr r  ⍝ Datetime
          :Case 16 ⋄ r←{(×⍵)×{⍵-2000 1 1 0 0 0 0}∊10 ¯3 ⎕DT|⍵}To64Int r ⍝ Timespan
          :Case 17 ⋄ r←100 60⊤323 ⎕dr r ⍝ Minute
          :Case 18 ⋄ r←100 60 60⊤323 ⎕dr r ⍝ Second
          :Case 19 ⋄ r←100 60 60 1000⊤323 ⎕DR r ⍝ Time
          :Else
              ⎕SIGNAL
          :EndSelect
      :EndSelect
     
      :If atom ⋄ r←⍬⍴r ⋄ :EndIf
    ∇


    ∇ Make(address port credentials);rc;r;z;step
      :Access Public
      :Implements Constructor
     
      'Credentials must be single-byte char'⎕SIGNAL(80≠⎕DR credentials)/11
      {}#.DRC.Init''
      :If 0=0⊃z←#.DRC.Clt''address port'Raw'⊣step←'Connect'
          CLT←1⊃z ⍝ Extract Conga client name
      :AndIf 0=0⊃z←#.DRC.Send CLT((⎕UCS credentials),1 0)⊣step←'Send Handshake'
      :AndIf 0=0⊃z←#.DRC.Wait CLT⊣step←'Wait for confirmation'
      :AndIf (,1)≡3⊃z⊣step←'Check Q return code'
          LittleEndian←2=⊃Int32Bytes 2
      :Else
          ('Failed at step ',step,': ',,⍕z)⎕SIGNAL 11
      :EndIf
    ∇

    ∇ UnMake
      :Implements Destructor
      :Trap 0 ⍝ Ignore errors in teardown
          :If 0≠⍴CLT ⋄ {}DRC.Close CLT ⋄ :EndIf
      :EndTrap
    ∇

:EndClass
