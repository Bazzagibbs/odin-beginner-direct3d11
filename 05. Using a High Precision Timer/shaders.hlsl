cbuffer constants : register(b0) {
        float2 offset;
        float4 uniform_color;
};


struct VS_Input {
        float2 position : position;
};


struct V2P {
        float4 position : SV_POSITION;
        float4 color    : COLOR;
};


V2P vertex_main(VS_Input input) {
        V2P output;
        output.position = float4(input.position + offset, 0.0f, 1.0f);
        output.color = uniform_color;

        return output;
}


float4 pixel_main(V2P input) : SV_TARGET {
        return input.color;
}
