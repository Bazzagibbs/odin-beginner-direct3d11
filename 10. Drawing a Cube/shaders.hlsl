cbuffer constants : register(b0) {
        float4x4 model_view_projection;
};


struct VS_Input {
        float3 position  : position;
        float3 color     : color;
};


struct V2P {
        float4 position  : SV_POSITION;
        float3 color     : COLOR;
};


V2P vertex_main(VS_Input input) {
        V2P output;
        output.position = mul(model_view_projection, float4(input.position, 1.0f));
        output.color    = input.color;

        return output;
}

float4 pixel_main(V2P input) : SV_TARGET {
        return float4(input.color, 1.0f);
}
