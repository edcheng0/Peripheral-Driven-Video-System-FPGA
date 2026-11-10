`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// ov7670_rom.v - GENERATED FILE (do not edit by hand).
//
// OV7670 register sequence: soft reset, OmniVision default settings, then
// QVGA (320x240, QVGA=1) or VGA (640x480, QVGA=0) + RGB565 output. Register
// addresses/values are taken from the
// open-source Linux V4L2 OV7670 driver (drivers/media/i2c/ov7670.c), whose
// default table is documented there as obtained from OmniVision. Only the
// register numbers/values are used here; the sequence is assembled by a script.
// Entry address 8'hFF means "wait" (not a register write).
// Last entry (TEST_BARS=1 only): SCALING_YSC bit 7 = 8-bar color test pattern.
// Not checked against the OmniVision datasheet PDF (could not read it).
// ----------------------------------------------------------------------
module ov7670_rom #(parameter TEST_BARS = 0, parameter QVGA = 1) (
    input  wire [8:0] idx,
    output reg  [7:0] addr,
    output reg  [7:0] data,
    output wire [8:0] last     // index of the final entry to send
);
    assign last = TEST_BARS ? 9'd179 : 9'd178;
    always @(*) begin
        case (idx)
            9'd0: begin addr = 8'hFF; data = 8'h00; end
            9'd1: begin addr = 8'h12; data = 8'h80; end
            9'd2: begin addr = 8'hFF; data = 8'h00; end
            9'd3: begin addr = 8'h11; data = 8'h01; end
            9'd4: begin addr = 8'h3A; data = 8'h04; end
            9'd5: begin addr = 8'h12; data = 8'h00; end
            9'd6: begin addr = 8'h17; data = 8'h13; end
            9'd7: begin addr = 8'h18; data = 8'h01; end
            9'd8: begin addr = 8'h32; data = 8'hB6; end
            9'd9: begin addr = 8'h19; data = 8'h02; end
            9'd10: begin addr = 8'h1A; data = 8'h7A; end
            9'd11: begin addr = 8'h03; data = 8'h0A; end
            9'd12: begin addr = 8'h0C; data = 8'h00; end
            9'd13: begin addr = 8'h3E; data = 8'h00; end
            9'd14: begin addr = 8'h70; data = 8'h3A; end
            9'd15: begin addr = 8'h71; data = 8'h35; end
            9'd16: begin addr = 8'h72; data = 8'h11; end
            9'd17: begin addr = 8'h73; data = 8'hF0; end
            9'd18: begin addr = 8'hA2; data = 8'h02; end
            9'd19: begin addr = 8'h15; data = 8'h00; end
            9'd20: begin addr = 8'h7A; data = 8'h20; end
            9'd21: begin addr = 8'h7B; data = 8'h10; end
            9'd22: begin addr = 8'h7C; data = 8'h1E; end
            9'd23: begin addr = 8'h7D; data = 8'h35; end
            9'd24: begin addr = 8'h7E; data = 8'h5A; end
            9'd25: begin addr = 8'h7F; data = 8'h69; end
            9'd26: begin addr = 8'h80; data = 8'h76; end
            9'd27: begin addr = 8'h81; data = 8'h80; end
            9'd28: begin addr = 8'h82; data = 8'h88; end
            9'd29: begin addr = 8'h83; data = 8'h8F; end
            9'd30: begin addr = 8'h84; data = 8'h96; end
            9'd31: begin addr = 8'h85; data = 8'hA3; end
            9'd32: begin addr = 8'h86; data = 8'hAF; end
            9'd33: begin addr = 8'h87; data = 8'hC4; end
            9'd34: begin addr = 8'h88; data = 8'hD7; end
            9'd35: begin addr = 8'h89; data = 8'hE8; end
            9'd36: begin addr = 8'h13; data = 8'hE0; end
            9'd37: begin addr = 8'h00; data = 8'h00; end
            9'd38: begin addr = 8'h10; data = 8'h00; end
            9'd39: begin addr = 8'h0D; data = 8'h40; end
            9'd40: begin addr = 8'h14; data = 8'h18; end
            9'd41: begin addr = 8'hA5; data = 8'h05; end
            9'd42: begin addr = 8'hAB; data = 8'h07; end
            9'd43: begin addr = 8'h24; data = 8'h95; end
            9'd44: begin addr = 8'h25; data = 8'h33; end
            9'd45: begin addr = 8'h26; data = 8'hE3; end
            9'd46: begin addr = 8'h9F; data = 8'h78; end
            9'd47: begin addr = 8'hA0; data = 8'h68; end
            9'd48: begin addr = 8'hA1; data = 8'h03; end
            9'd49: begin addr = 8'hA6; data = 8'hD8; end
            9'd50: begin addr = 8'hA7; data = 8'hD8; end
            9'd51: begin addr = 8'hA8; data = 8'hF0; end
            9'd52: begin addr = 8'hA9; data = 8'h90; end
            9'd53: begin addr = 8'hAA; data = 8'h94; end
            9'd54: begin addr = 8'h13; data = 8'hE5; end
            9'd55: begin addr = 8'h0E; data = 8'h61; end
            9'd56: begin addr = 8'h0F; data = 8'h4B; end
            9'd57: begin addr = 8'h16; data = 8'h02; end
            9'd58: begin addr = 8'h1E; data = 8'h07; end
            9'd59: begin addr = 8'h21; data = 8'h02; end
            9'd60: begin addr = 8'h22; data = 8'h91; end
            9'd61: begin addr = 8'h29; data = 8'h07; end
            9'd62: begin addr = 8'h33; data = 8'h0B; end
            9'd63: begin addr = 8'h35; data = 8'h0B; end
            9'd64: begin addr = 8'h37; data = 8'h1D; end
            9'd65: begin addr = 8'h38; data = 8'h71; end
            9'd66: begin addr = 8'h39; data = 8'h2A; end
            9'd67: begin addr = 8'h3C; data = 8'h78; end
            9'd68: begin addr = 8'h4D; data = 8'h40; end
            9'd69: begin addr = 8'h4E; data = 8'h20; end
            9'd70: begin addr = 8'h69; data = 8'h00; end
            9'd71: begin addr = 8'h6B; data = 8'h4A; end
            9'd72: begin addr = 8'h74; data = 8'h10; end
            9'd73: begin addr = 8'h8D; data = 8'h4F; end
            9'd74: begin addr = 8'h8E; data = 8'h00; end
            9'd75: begin addr = 8'h8F; data = 8'h00; end
            9'd76: begin addr = 8'h90; data = 8'h00; end
            9'd77: begin addr = 8'h91; data = 8'h00; end
            9'd78: begin addr = 8'h96; data = 8'h00; end
            9'd79: begin addr = 8'h9A; data = 8'h00; end
            9'd80: begin addr = 8'hB0; data = 8'h84; end
            9'd81: begin addr = 8'hB1; data = 8'h0C; end
            9'd82: begin addr = 8'hB2; data = 8'h0E; end
            9'd83: begin addr = 8'hB3; data = 8'h82; end
            9'd84: begin addr = 8'hB8; data = 8'h0A; end
            9'd85: begin addr = 8'h43; data = 8'h0A; end
            9'd86: begin addr = 8'h44; data = 8'hF0; end
            9'd87: begin addr = 8'h45; data = 8'h34; end
            9'd88: begin addr = 8'h46; data = 8'h58; end
            9'd89: begin addr = 8'h47; data = 8'h28; end
            9'd90: begin addr = 8'h48; data = 8'h3A; end
            9'd91: begin addr = 8'h59; data = 8'h88; end
            9'd92: begin addr = 8'h5A; data = 8'h88; end
            9'd93: begin addr = 8'h5B; data = 8'h44; end
            9'd94: begin addr = 8'h5C; data = 8'h67; end
            9'd95: begin addr = 8'h5D; data = 8'h49; end
            9'd96: begin addr = 8'h5E; data = 8'h0E; end
            9'd97: begin addr = 8'h6C; data = 8'h0A; end
            9'd98: begin addr = 8'h6D; data = 8'h55; end
            9'd99: begin addr = 8'h6E; data = 8'h11; end
            9'd100: begin addr = 8'h6F; data = 8'h9F; end
            9'd101: begin addr = 8'h6A; data = 8'h40; end
            9'd102: begin addr = 8'h01; data = 8'h40; end
            9'd103: begin addr = 8'h02; data = 8'h60; end
            9'd104: begin addr = 8'h13; data = 8'hE7; end
            9'd105: begin addr = 8'h4F; data = 8'h80; end
            9'd106: begin addr = 8'h50; data = 8'h80; end
            9'd107: begin addr = 8'h51; data = 8'h00; end
            9'd108: begin addr = 8'h52; data = 8'h22; end
            9'd109: begin addr = 8'h53; data = 8'h5E; end
            9'd110: begin addr = 8'h54; data = 8'h80; end
            9'd111: begin addr = 8'h58; data = 8'h9E; end
            9'd112: begin addr = 8'h41; data = 8'h08; end
            9'd113: begin addr = 8'h3F; data = 8'h00; end
            9'd114: begin addr = 8'h75; data = 8'h05; end
            9'd115: begin addr = 8'h76; data = 8'hE1; end
            9'd116: begin addr = 8'h4C; data = 8'h00; end
            9'd117: begin addr = 8'h77; data = 8'h01; end
            9'd118: begin addr = 8'h3D; data = 8'hC3; end
            9'd119: begin addr = 8'h4B; data = 8'h09; end
            9'd120: begin addr = 8'hC9; data = 8'h60; end
            9'd121: begin addr = 8'h41; data = 8'h38; end
            9'd122: begin addr = 8'h56; data = 8'h40; end
            9'd123: begin addr = 8'h34; data = 8'h11; end
            9'd124: begin addr = 8'h3B; data = 8'h12; end
            9'd125: begin addr = 8'hA4; data = 8'h88; end
            9'd126: begin addr = 8'h96; data = 8'h00; end
            9'd127: begin addr = 8'h97; data = 8'h30; end
            9'd128: begin addr = 8'h98; data = 8'h20; end
            9'd129: begin addr = 8'h99; data = 8'h30; end
            9'd130: begin addr = 8'h9A; data = 8'h84; end
            9'd131: begin addr = 8'h9B; data = 8'h29; end
            9'd132: begin addr = 8'h9C; data = 8'h03; end
            9'd133: begin addr = 8'h9D; data = 8'h4C; end
            9'd134: begin addr = 8'h9E; data = 8'h3F; end
            9'd135: begin addr = 8'h78; data = 8'h04; end
            9'd136: begin addr = 8'h79; data = 8'h01; end
            9'd137: begin addr = 8'hC8; data = 8'hF0; end
            9'd138: begin addr = 8'h79; data = 8'h0F; end
            9'd139: begin addr = 8'hC8; data = 8'h00; end
            9'd140: begin addr = 8'h79; data = 8'h10; end
            9'd141: begin addr = 8'hC8; data = 8'h7E; end
            9'd142: begin addr = 8'h79; data = 8'h0A; end
            9'd143: begin addr = 8'hC8; data = 8'h80; end
            9'd144: begin addr = 8'h79; data = 8'h0B; end
            9'd145: begin addr = 8'hC8; data = 8'h01; end
            9'd146: begin addr = 8'h79; data = 8'h0C; end
            9'd147: begin addr = 8'hC8; data = 8'h0F; end
            9'd148: begin addr = 8'h79; data = 8'h0D; end
            9'd149: begin addr = 8'hC8; data = 8'h20; end
            9'd150: begin addr = 8'h79; data = 8'h09; end
            9'd151: begin addr = 8'hC8; data = 8'h80; end
            9'd152: begin addr = 8'h79; data = 8'h02; end
            9'd153: begin addr = 8'hC8; data = 8'hC0; end
            9'd154: begin addr = 8'h79; data = 8'h03; end
            9'd155: begin addr = 8'hC8; data = 8'h40; end
            9'd156: begin addr = 8'h79; data = 8'h05; end
            9'd157: begin addr = 8'hC8; data = 8'h30; end
            9'd158: begin addr = 8'h79; data = 8'h26; end
            9'd159: begin addr = 8'h12; data = QVGA ? 8'h14 : 8'h04; end
            9'd160: begin addr = 8'h8C; data = 8'h00; end
            9'd161: begin addr = 8'h04; data = 8'h00; end
            9'd162: begin addr = 8'h40; data = 8'h10; end
            9'd163: begin addr = 8'h14; data = 8'h38; end
            9'd164: begin addr = 8'h4F; data = 8'hB3; end
            9'd165: begin addr = 8'h50; data = 8'hB3; end
            9'd166: begin addr = 8'h51; data = 8'h00; end
            9'd167: begin addr = 8'h52; data = 8'h3D; end
            9'd168: begin addr = 8'h53; data = 8'hA7; end
            9'd169: begin addr = 8'h54; data = 8'hE4; end
            9'd170: begin addr = 8'h3D; data = 8'hC0; end
            9'd171: begin addr = 8'h15; data = 8'h00; end
            9'd172: begin addr = 8'h17; data = QVGA ? 8'h15 : 8'h13; end
            9'd173: begin addr = 8'h18; data = QVGA ? 8'h03 : 8'h01; end
            9'd174: begin addr = 8'h32; data = QVGA ? 8'h80 : 8'hB6; end
            9'd175: begin addr = 8'h19; data = QVGA ? 8'h03 : 8'h02; end
            9'd176: begin addr = 8'h1A; data = QVGA ? 8'h7B : 8'h7A; end
            9'd177: begin addr = 8'h03; data = QVGA ? 8'h00 : 8'h0A; end
            9'd178: begin addr = 8'h11; data = 8'h01; end
            9'd179: begin addr = 8'h71; data = 8'hB5; end
            default: begin addr = 8'hFF; data = 8'h00; end
        endcase
    end
endmodule
