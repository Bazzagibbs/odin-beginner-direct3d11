cbuffer constants_vertex : register(b0) {
        float4x4 model_view_projection;
        float4x4 model_view;
        float3x3 normal_matrix;
};


struct Directional_Light {
        float4 direction_to_light_eye; // surface TO light
        float4 color;
};


struct Point_Light {
        float4 position_eye;
        float4 color;
};


cbuffer constants_pixel : register(b0) {
        Directional_Light directional_light;
        Point_Light point_lights[2];
};


struct VS_Input {
        float3 position  : POSITION;
        float2 tex_coord : TEXCOORD;
        float3 normal    : NORMAL;
};


struct V2P {
        float4 position     : SV_POSITION;
        float3 position_eye : POSITION;
        float3 normal_eye   : NORMAL;
        float2 tex_coord    : TEXCOORD;
};


V2P vertex_main(VS_Input input) {
        V2P output;
        output.position     = mul(model_view_projection, float4(input.position, 1.0));
        output.position_eye = mul(model_view, float4(input.position, 1.0)).xyz;
        output.normal_eye   = mul(normal_matrix, input.normal);
        output.tex_coord    = input.tex_coord;

        return output;
}


Texture2D _texture    : register(t0);
SamplerState _sampler : register(s0);

float4 pixel_main(V2P input) : SV_TARGET {
        float3 normal = normalize(input.normal_eye); // interpolation denormalizes

        // float3 diffuse_color = _texture.Sample(_sampler, input.tex_coord).xyz;
        float3 diffuse_color = float3(0.2, 0.2, 0.2);

        float3 frag_to_cam_direction = normalize(-input.position_eye);

        float3 directional_intensity;
        {
                float ambient_strength  = 0.1;
                float specular_strength = 0.9;
                float specular_exponent = 100;
                float3 light_color      = directional_light.color.xyz;

                float3 light_direction_eye = directional_light.direction_to_light_eye.xyz;
                float diffuse_factor = max(0.0, dot(normal, light_direction_eye));

                float3 halfway_eye = normalize(frag_to_cam_direction + light_direction_eye);
                float specular_factor = max(0.0, dot(halfway_eye, normal));
                float3 specular_intensity = specular_strength * pow(specular_factor, 2 * specular_exponent);

                directional_intensity = (ambient_strength + diffuse_factor + specular_intensity) * light_color;
        }
        
        float3 point_light_intensity = float3(0.0, 0.0, 0.0);
        [unroll]
        for (int i = 0; i < 2; i += 1) {
                float ambient_strength  = 0.1;
                float specular_strength = 0.9;
                float specular_exponent = 100;
                float3 light_color      = point_lights[i].color.xyz;

                float3 light_direction_eye = point_lights[i].position_eye - input.position_eye;
                float inverse_distance = 1.0 / length(light_direction_eye);
                light_direction_eye *= inverse_distance; // normalize
                
                
                float diffuse_factor = max(0.0, dot(normal, light_direction_eye));

                float3 halfway_eye = normalize(frag_to_cam_direction + light_direction_eye);
                float specular_factor = max(0.0, dot(halfway_eye, normal));
                float3 specular_intensity = specular_strength * pow(specular_factor, 2 * specular_exponent);

                point_light_intensity += (ambient_strength + diffuse_factor + specular_intensity) * light_color;
        }

        float3 result = (directional_intensity + point_light_intensity) * diffuse_color;
        return float4(result, 1.0);
}
