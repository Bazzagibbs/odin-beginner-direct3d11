cbuffer constants : register(b0) {
        float3 offset;
};


struct VS_Input {
        float2 position  : position;
        float2 tex_coord : tex_coord;
};


struct V2P {
        float4 position  : SV_POSITION;
        float2 tex_coord : TEXCOORD;
};


V2P vertex_main(VS_Input input) {
        V2P output;
        output.position = float4(input.position + offset.xy, offset.z, 1.0f);
        output.tex_coord = input.tex_coord;

        return output;
}

Texture2D _texture    : register(t0);
SamplerState _sampler : register(s0);

float4 pixel_main(V2P input) : SV_TARGET {
        return _texture.Sample(_sampler, input.tex_coord);
}
